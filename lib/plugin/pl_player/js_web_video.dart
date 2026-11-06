import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:PiliPlus/http/browser_ua.dart';
import 'package:PiliPlus/main.dart' show webViewEnvironment;
import 'package:PiliPlus/plugin/pl_player/js_web_player.dart';
import 'package:PiliPlus/services/runtime_log.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:material_ui/material_ui.dart';

/// JS 后端的视频渲染面。
///
/// 与 [FvpVideo] 保持相同的构造参数，便于在 `PLVideoPlayer` 中按后端切换。
/// 区别：原生后端用 `Texture(textureId)`，这里整块是 WebView。
///
/// 页面不通过 `loadData` 注入——Windows 实现走 `NavigateToString`，会丢掉
/// `baseUrl`，页面就失去 bilibili.com 源，媒体分段请求也会没有 Bilibili 的
/// `Referer`，CDN 直接拒绝。改为用 `shouldInterceptRequest` 应答一个
/// bilibili.com 的虚拟页面 URL，页面源和 Referer 才都是对的。
class JsWebVideo extends StatefulWidget {
  const JsWebVideo({
    super.key,
    required this.controller,
    this.fill = Colors.black,
    this.aspectRatio,
  });

  final JsWebPlayer controller;
  final Color fill;
  final double? aspectRatio;

  @override
  State<JsWebVideo> createState() => _JsWebVideoState();
}

class _JsWebVideoState extends State<JsWebVideo> {
  bool _pageLoaded = false;

  /// dash.js 源只在拼页面时用一次，之后只留拼好的 shell。
  /// 同时持有两份 ~800KB 字符串会让 Dart 堆常驻多 1MB 左右。
  String? _shellSource;

  @override
  void initState() {
    super.initState();
    unawaited(_loadAssets());
  }

  Future<void> _loadAssets() async {
    try {
      // 两个库都要用，一次并行读完再拼页面，避免拼两次字符串。
      final results = await Future.wait([
        rootBundle.loadString(JsWebPlayer.dashJsAsset),
        rootBundle.loadString(JsWebPlayer.hlsJsAsset),
      ]);
      final shell = _buildDashShell(results[0], results[1]);
      RuntimeLog.info(
        'DASH.js asset loaded chars=${results[0].length} '
        'hls.js chars=${results[1].length}',
      );
      if (!mounted) return;
      setState(() => _shellSource = shell);
    } catch (error) {
      RuntimeLog.error('DASH.js asset load failed', error);
    }
  }

  /// 应答播放器页面；dash.js 已经内联在页面里，媒体分段交给 CDN 正常请求。
  Future<WebResourceResponse?> _intercept(
    InAppWebViewController controller,
    WebResourceRequest request,
  ) async {
    final url = request.url.toString();
    if (url != JsWebPlayer.playerPageUrl) return null;
    final shell = _shellSource;
    if (shell == null) {
      RuntimeLog.warning('DASH.js page requested before shell was built');
      return null;
    }
    RuntimeLog.info('DASH.js player page served');
    return WebResourceResponse(
      contentType: 'text/html',
      contentEncoding: 'utf-8',
      data: Uint8List.fromList(utf8.encode(shell)),
      statusCode: 200,
      reasonPhrase: 'OK',
    );
  }

  void _onPageMessage(dynamic message) {
    if (message is! Map) return;
    final type = message['type'];
    final data = message['data'];
    switch (type) {
      case 'ready':
        widget.controller.reportPageReady();
      case 'meta':
        widget.controller.handleMessage('meta', jsonEncode(data));
      case 'state':
        widget.controller.handleMessage('state', jsonEncode(data));
      case 'time':
        widget.controller.handleMessage('time', jsonEncode(data));
      case 'ended':
        widget.controller.handleMessage('ended', jsonEncode(data));
      case 'error':
        widget.controller.handleMessage('error', data?.toString() ?? 'unknown');
      case 'log':
        RuntimeLog.info('DASH.js ${data ?? ''}');
    }
  }

  @override
  void dispose() {
    _shellSource = null;
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant JsWebVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _pageLoaded = false;
    }
  }

  /// 播放器页面。dash.js / hls.js 由 [JsWebVideo] 内联进这个页面，不发外网请求。
  String _buildDashShell(String dashJsSource, String hlsJsSource) {
    const html = r'''
<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<style>html,body,#v{width:100%;height:100%;margin:0;background:#000;overflow:hidden}#v{object-fit:contain}</style>
</head>
<body><video id="v" playsinline crossorigin="anonymous"></video>
<script>
(function(){
 var v=document.getElementById('v'),videoPlayer=null,videoBlob=null,opened=null,booted=false,hls=null;
 var notify=function(type,data){try{window.flutter_inappwebview.callHandler('dashMessage',{type:type,data:data});}catch(e){}};
 function fail(where,error){notify('error',where+': '+((error&&error.message)||error||'unknown'));}
 // 库就绪前不上报全局错误：那段窗口里的失败只是“还没准备好”，不是真故障。
 window.onerror=function(msg,src,line,col){if(!booted)return false;fail('page script',msg+' at line '+line+':'+col);return false;};
 window.addEventListener('unhandledrejection',function(e){if(!booted)return;fail('page promise',e.reason);});
 function esc(s){return String(s==null?'':s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');}
 function range(v){if(typeof v==='string')return v;if(v&&typeof v==='object'&&v.start!==undefined)return v.start+'-'+v.end;return '';}
 // 单个 AdaptationSet / Representation。B 站 DASH 是每路一个独立 fMP4 文件
 // （SegmentBase + indexRange），视频轨和音频轨合成一个 MPD 时各占一个
 // AdaptationSet，BaseURL 指向各自的文件。
 function adaptationSet(base,track,id,video){
  // 接口两种写法都发：SegmentBase/Initialization/indexRange 与
  // segment_base/initialization/index_range，取值要都认。
  var segment=track.segmentBase||track.SegmentBase||{}, init=segment.Initialization||segment.initialization||{}, index=segment.indexRange||segment.IndexRange||segment.index_range||'';
  var initRange=range(init.range||init), indexRange=range(index);
  var mime=track.mimeType||(video?'video/mp4':'audio/mp4'), codecs=track.codecs||'';
  var dims=video?' width="'+(track.width||1280)+'" height="'+(track.height||720)+'"':'';
  return '<AdaptationSet id="'+id+'" contentType="'+(video?'video':'audio')+'" segmentAlignment="true"><Representation id="'+id+'" bandwidth="'+(track.bandWidth||1000000)+'" mimeType="'+esc(mime)+'" codecs="'+esc(codecs)+'"'+dims+'><BaseURL>'+esc(base)+'</BaseURL><SegmentBase indexRange="'+esc(indexRange)+'"><Initialization range="'+esc(initRange)+'"/></SegmentBase></Representation></AdaptationSet>';
 }
 // 音视频合并成单个 MPD。这样只用一个 dash.js 实例、一个 <video>、一套 MSE 缓冲，
 // 浏览器以音频时钟为主时钟自动同步 A/V；拆成两个元素时各自走独立时钟，长时间
 // 播放会漂移（音画不同步/反复卡顿），且双倍播放器与缓冲内存。
 function manifestXml(videoBase,audioBase,duration,videoTrack,audioTrack){
  var period='<Period duration="PT'+duration+'S">'+adaptationSet(videoBase,videoTrack,'video',true);
  if(audioBase&&audioTrack&&(audioTrack.segmentBase||audioTrack.SegmentBase)){
   period+=adaptationSet(audioBase,audioTrack,'audio',false);
  }
  period+='</Period>';
  return '<?xml version="1.0"?><MPD xmlns="urn:mpeg:dash:schema:mpd:2011" type="static" profiles="urn:mpeg:dash:profile:isoff-on-demand:2011" mediaPresentationDuration="PT'+duration+'S">'+period+'</MPD>';
 }
 // 换源时先 reset() 释放 MSE 缓冲再 revoke URL；旧 SourceBuffer 里的帧会跟着
 // 播放器实例一起多活一轮，是 JS 后端内存占用的来源之一。
 // 定位“点了播放却不播”：把 dash.js 的关键内部状态和关键事件都打到日志里。
 var traceLast={};
 function trace(tag){
  if(!window.dashjs||!window.dashjs.MediaPlayer)return;
  try{
   notify('log','trace '+tag+
    ' autoplay='+(videoPlayer&&videoPlayer.getAutoPlay&&videoPlayer.getAutoPlay())+
    ' paused='+(videoPlayer&&videoPlayer.isPaused&&videoPlayer.isPaused())+
    ' stalled='+(videoPlayer&&videoPlayer.getPlaybackStalled&&videoPlayer.getPlaybackStalled())+
    ' ready='+(videoPlayer&&videoPlayer.isReady&&videoPlayer.isReady())+
    ' readyState='+v.readyState+' elPaused='+v.paused+
    ' buffered='+(v.buffered.length?v.buffered.end(v.buffered.length-1).toFixed(2):'0')+
    ' ct='+v.currentTime.toFixed(2));
  }catch(e){notify('log','trace failed '+tag+': '+e);}
 }
 function attachTrace(player,who){
  if(!player||!player.on)return;
  var ev=dashjs.MediaPlayer.events||{};
  [['PLAYBACK_PLAYING','PLAYING'],['PLAYBACK_PAUSED','PAUSED'],['PLAYBACK_STALLED','STALLED'],['PLAYBACK_WAITING','WAITING'],['BUFFER_LEVEL_STATE_CHANGED','BUFSTATE'],['PLAYBACK_SEEKED','SEEKED'],['PLAYBACK_NOT_ALLOWED','NOT_ALLOWED'],['MANIFEST_LOADED','MANIFEST'],['ERROR','DASHERROR']].forEach(function(p){
   if(!ev[p[0]])return;
   try{player.on(ev[p[0]],function(){notify('log','event '+who+' '+p[1]);});}catch(e){}
  });
  if(ev.PLAYBACK_TIME_UPDATED){try{player.on(ev.PLAYBACK_TIME_UPDATED,function(){var n=Date.now();if(n-(traceLast[who]||0)>2000){traceLast[who]=n;trace(who+' tick');}});}catch(e){}}
 }
 function destroy(player){
  if(!player)return;
  try{player.pause();}catch(e){}
  // reset() 会 detachMediaSource + 清空 streamController，已 append 的帧随之释放。
  try{player.reset();}catch(e){}
 }
 function stop(){
  if(hls){try{hls.destroy();}catch(e){}hls=null;}
  destroy(videoPlayer);videoPlayer=null;
  if(videoBlob){try{URL.revokeObjectURL(videoBlob);}catch(e){}videoBlob=null;}
  v.pause();
  // removeAttribute('src') 会触发 MSE 的 load()，把已 append 的数据全丢掉；
  // 换源时 dash.js 自己会 detachMediaSource，不需要这步。
 }
 // 起播窗口内的兜底重试：dash.js 的 play() 在 manifest 解析完成前会静默丢弃
 // （原因见下），而它的 gate 是同步的，调用返回后元素还是 paused。
 var pendingTimer=null,pendingCount=0;
 function pendingTick(){
  if(v.paused||!pendingTimer)return;
  clearInterval(pendingTimer);pendingTimer=null;
  notify('log','pending play satisfied after '+pendingCount+' retries');
 }
 function armPending(){
  if(pendingTimer)return;
  pendingCount=0;
  pendingTimer=setInterval(function(){pendingCount++;pendingTick();},150);
  setTimeout(function(){if(pendingTimer){clearInterval(pendingTimer);pendingTimer=null;notify('log','pending play gave up after '+pendingCount+' retries');}},8000);
 }
 function elementPlay(el,who){
  try{var p=el.play();if(p&&p.catch)p.catch(function(e){if(!/interrupted by a call to pause/.test((e&&e.message)||''))fail(who+' play',e);});}
  catch(e){fail(who+' play',e);}
 }
 function play(){
  notify('log','play called videoPlayer='+(!!videoPlayer)+' paused='+v.paused+' readyState='+v.readyState+' autoplay='+(opened&&opened.autoplay)+' isReady='+(videoPlayer&&videoPlayer.isReady&&videoPlayer.isReady()));
  // dash.js 的 play() 只在“元素已暂停”时才会走到 PlaybackController.play()，
  // 而它的 isPaused() 在 manifest 解析完成前返回 null（还没有激活的 streamInfo），
  // 于是 (!autoplay || isPaused()) 求值为 null，W.play() 根本不会被调用，也不设置
  // 待播标记——播放请求被静默丢弃，这正是“点一次播放没反应，必须再点一次”的原因。
  // 所以这里以元素状态为准：调过 dash.js 之后元素还是 paused，就直接对元素起播。
  // autoplay=true 时 dash.js 的调度器本来就在拉流，元素起播即可。
  if(videoPlayer){
   try{trace('play entry');videoPlayer.play();trace('play exit');}catch(e){}
   // 只有还没拿到数据时才需要兜底重试；已经缓冲好的话 dash.js 丢了这次请求就是
   // 真的被拒了，重试只会白跑一个 8s 定时器。
   if(v.paused){notify('log','dash play did not resume, falling back to element');elementPlay(v,'video');if(v.readyState<2)armPending();}
  }else{elementPlay(v,'video');}
 }
 // dash.js 默认按 30s/60s 长视频缓冲，低配机器上这一段就是几十 MB。
 // 只压缓冲，不动 abr.maxBitrate——单 Representation 的 MPD 一旦被 ABR 过滤掉，
 // 整个流就没有可用轨道了。
 // 单 Representation 的 MPD 永远处于“最高质量”，dash.js 的 isTopQuality() 为真时
 // 用的是 bufferTimeAtTopQuality/bufferTimeAtTopQualityLongForm，bufferTimeDefault
 // 根本不生效。日志里实测缓冲停在 15s（并随每次卡顿涨到 30s），就是这个原因——
 // 不是设的 4s。三个值要一起设，目标缓冲才真正是下面这几秒，而不是 dash.js 默认的
 // 30s/60s（1080p60 每路会吃掉几十 MB，WebView 渲染进程内存随之高企）。
 function applyBufferSettings(player,infinite){
  if(!player||!player.updateSettings)return;
  try{
   player.updateSettings({
    streaming:{
     buffer:{
      bufferTimeAtTopQuality:6,
      bufferTimeAtTopQualityLongForm:8,
      bufferTimeDefault:6,
      initialBufferLevel:2,
      bufferToKeep:8,
      bufferPruningInterval:5,
      fastSwitchEnabled:false,
      // 只有时长未知（d.duration<=0）才把 MSE duration 设成 Infinity；点播必须给
      // 有限时长。dash.js 5.x 默认 mediaSourceDurationInfinity=true，会把点播当
      // live 处理：缓冲窗变成滑窗，buffer end 钉在播放头前方固定偏移，网络一慢
      // 播放头就追上窗沿，出现“放一会儿就卡一下”的反复缓冲（日志里 6s 卡顿）。
      mediaSourceDurationInfinity:!!infinite,
      // dash.js 默认把 600s 以上的内容当长视频，用 60s 缓冲目标；B 站大多数
      // 稿件只有几分钟，不把阈值抬起来的话，长视频分支基本永远走不到。
      longFormContentDurationThreshold:86400
     },
     scheduling:{scheduleWhilePaused:false},
     text:{defaultEnabled:false},
     metrics:{maxListDepth:20},
     wallclockTimeUpdateInterval:250
    }
   });
  }catch(e){notify('log','buffer settings failed: '+((e&&e.message)||e));}
 }
 // dash.js 的事件要在 initialize() 之前挂上，否则它初始化时自己触发的那一批
 // PLAYING/PAUSED 会丢，页面状态就永远停在旧值上。
 function attachEvents(player,element,who){
  var events=dashjs.MediaPlayer.events;
  player.on(events.ERROR,function(e){fail(who+' DASH.js',(e&&e.error)||e);});
  player.on(events.MANIFEST_LOADED,function(){notify('log',who+' manifest loaded');});
  player.on(events.PLAYBACK_METADATA_LOADED,function(){notify('log',who+' metadata loaded');});
  player.on(events.PLAYBACK_PLAYING,function(){notify('log',who+' playing');notify('state',{playing:true,buffering:false});});
  player.on(events.PLAYBACK_PAUSED,function(){notify('state',{playing:false,buffering:false});});
  player.on(events.PLAYBACK_WAITING,function(){notify('state',{playing:!element.paused,buffering:true});});
  player.on(events.PLAYBACK_ENDED,function(){notify('ended',{});});
  // dash.js 在没有任何一次 play() 真正生效时不会发 PLAYBACK_PLAYING，但元素上的
  // play() 一定会先触发 playing 事件——用它把“兜底起播”同步回 Dart。
  element.addEventListener('playing',function(){notify('state',{playing:true,buffering:false});});
  attachTrace(player,who);
 }
 // 直播流不是 DASH：接口的 http_hls 实际是 fmp4 分片，交给 hls.js 走 MSE。
 // 判据用 URL 形态，不依赖调用方传 isLive——直播和点播都可能有 m3u8。
 function isOpenHls(u){
  return /\.m3u8(?:[?#]|$)/i.test(String(u||''));
 }
 function openHls(url,autoplay){
  if(!window.Hls||!window.Hls.isSupported()){fail('HLS load',new Error('hls.js unavailable'));return;}
  hls=new window.Hls({lowLatencyMode:false,enableWorker:true});
  hls.on(window.Hls.Events.ERROR,function(ev,data){
   if(data&&data.fatal){fail('HLS',new Error(data.type+' '+(data.details||'')));}
   else{notify('log','hls non-fatal error '+(data&&data.details));}
  });
  hls.on(window.Hls.Events.MANIFEST_PARSED,function(){notify('log','hls manifest parsed levels='+(hls.levels?hls.levels.length:0));});
  hls.on(window.Hls.Events.LEVEL_LOADED,function(ev,data){
   if(data&&data.details){
    var live=!!data.details.live;
    notify('log','hls level loaded live='+live+' dur='+(data.details.totalduration||0).toFixed(2));
   }
  });
  hls.loadSource(url);
  hls.attachMedia(v);
  // attachMedia 之后 hls.js 会自己起播；元素状态由 playing 事件同步回 Dart。
  v.volume=Number(opened.volume);
  if(autoplay){elementPlay(v,'video');}
 }
 function open(d){
  stop();opened=d;
  if(!(window.dashjs&&window.dashjs.MediaPlayer)&&!(window.Hls&&window.Hls.isSupported)){
   fail('DASH.js load',new Error('player libraries missing'));return;
  }
  try{
   if(isOpenHls(d.video)){notify('log','HLS open '+d.video);openHls(d.video,!!d.autoplay);return;}
   if(!(window.dashjs&&window.dashjs.MediaPlayer)){fail('DASH.js load',new Error('dash.js library missing'));return;}
   // 点播时长已知（d.duration>0）用有限 MSE 时长；未知（0）退回 Infinity，避免
   // PT0S 的 MPD 打不开。直播走 hls.js，不经过这里。
   var infiniteDuration=!(d.duration>0);
   // 音频轨缺失时不能整段放弃：视频轨照常播，只是没有声音轨。
   var hasVideo=!!(d.videoTrack&&(d.videoTrack.segmentBase||d.videoTrack.SegmentBase));
   var hasAudio=!!(d.audioTrack&&(d.audioTrack.segmentBase||d.audioTrack.SegmentBase));
   if(!hasVideo)throw new Error('video segmentBase missing');
   // 视频+音频合并成单个 MPD / 单个 <video> / 单个 dash.js 实例（见 manifestXml）。
   var dashXml=manifestXml(d.video,hasAudio?d.audio:null,d.duration||0,d.videoTrack,hasAudio?d.audioTrack:null);
   videoBlob=URL.createObjectURL(new Blob([dashXml],{type:'application/dash+xml'}));
   videoPlayer=dashjs.MediaPlayer().create();
   attachEvents(videoPlayer,v,'video');
   // 第三个参数是 autoplay：dash.js 用它决定 PLAYBACK_PAUSED 时是否继续拉流
   // （scheduleWhilePaused=false 时，非 autoplay 的流会被停掉调度器）。
   videoPlayer.initialize(v,videoBlob,!!d.autoplay);
   // initialize() 内部会走一遍 reset()，settings.reset() 会把 updateSettings
   // 冲掉；必须在 initialize 之后再设一次，缓冲目标才真正生效。
   applyBufferSettings(videoPlayer,infiniteDuration);
   v.volume=Number(d.volume);v.playbackRate=Number(d.rate)||1;
   // autoplay 就在这里起播，不等 loadedmetadata。dash.js 的 play() 在 manifest
   // 解析完成前会静默丢弃（见 play() 里的说明），readyState 在 MSE 拿到第一段
   // 数据之前也一直是 0，所以等这两个条件等于永远不播。
   if(d.autoplay){trace('pre autoplay');play();trace('post autoplay');}
   else{trace('no autoplay');}
   // 起始位置要在元素起播前就位，否则 dash.js 已经把流推进到 0 秒附近，seek 就得
   // 重新缓冲，用户还会先看到几秒开头画面。起播前 currentTime 一定还是 0，所以
   // currentTime>0 就说明起播已经跑在 seek 前面了，直接放弃，别去追。
   var applied=false;
   function applyStart(why){
    if(applied)return;
    if(v.currentTime>0.01){applied=true;notify('log','start skip already at '+v.currentTime.toFixed(2)+' via '+why);return;}
    if(v.readyState<1){notify('log','start wait readyState='+v.readyState+' via '+why);return;}
    applied=true;
    try{videoPlayer&&videoPlayer.seek(d.start/1000);}catch(e){try{v.currentTime=d.start/1000;}catch(e2){}}
    notify('log','start applied '+d.start+'ms via '+why+' ct='+v.currentTime.toFixed(2));
   }
   if(d.start>0){
    v.addEventListener('loadedmetadata',function(){applyStart('metadata');},{once:true});
    setTimeout(function(){applyStart('timeout');},5000);
   }
   // 起播窗口只在前 20s：之后还打 trace 只会给每条日志加一次 JSON 桥往返。
   var traceTicks=0;
   var traceTimer=setInterval(function(){
    traceTicks++;trace('tick '+traceTicks);
    if(traceTicks>=20)clearInterval(traceTimer);
   },1000);
   notify('log','local DASH manifest created video='+hasVideo+' audio='+hasAudio+' autoplay='+!!d.autoplay);
  }catch(e){notify('error','DASH manifest setup: '+((e&&e.message)||e||'unknown'));}
 }
 window.__dashOpen=open;
 window.__dashCommand=function(m){
  if(!m)return;
  if(m.type==='play')play();
  else if(m.type==='pause'){trace('pause cmd');try{if(videoPlayer)videoPlayer.pause();}catch(e){}v.pause();}
  else if(m.type==='toggle'){trace('toggle cmd elPaused='+v.paused);if(v.paused)play();else{try{if(videoPlayer)videoPlayer.pause();}catch(e){}v.pause();}}
  else if(m.type==='seek'){trace('seek cmd t='+m.time);try{v.currentTime=m.time;}catch(e){}}
  else if(m.type==='rate'){v.playbackRate=m.rate;}
  else if(m.type==='volume'){v.volume=m.volume;}
 };
 v.addEventListener('loadedmetadata',function(){notify('log','video loadedmetadata '+v.videoWidth+'x'+v.videoHeight+' dur='+v.duration);notify('meta',{width:v.videoWidth,height:v.videoHeight,duration:v.duration});});
 // 进度位置不能只靠 timeupdate：MSE 挂上去之后 timeupdate 不一定按 ~4Hz 触发，
 // 一旦它停发，进度条就永远停在最后一次采样的位置（续播时会卡在 0）。
 // 所以自己按 500ms 采样，timeupdate 只作为补充信号。
 var lastNotify=0;
 function reportTime(why){
  var now=Date.now();
  if(now-lastNotify<500)return;
  lastNotify=now;
  var b=0;try{if(v.buffered.length)b=v.buffered.end(v.buffered.length-1);}catch(e){}
  // 直播的 duration 是 Infinity，直接过桥会变成 JSON 里的 Infinity（Dart 侧
  // double 接不住）。直播时长无意义，统一报 0，由 UI 走直播分支。
  var dur=v.duration;
  if(!isFinite(dur)||dur<0)dur=0;
  notify('time',{time:v.currentTime,buffer:b,duration:dur});
 }
 v.addEventListener('timeupdate',function(){reportTime('timeupdate');});
 // seek 后 currentTime 立刻就是新位置，等 timeupdate 会晚很久，所以立即补报一次。
 v.addEventListener('seeked',function(){lastNotify=0;reportTime('seeked');notify('log','seeked ct='+v.currentTime.toFixed(2));});
 // 暂停时也要报一次，否则最后那一段进度会丢。
 v.addEventListener('pause',function(){lastNotify=0;reportTime('pause');});
 v.addEventListener('ended',function(){lastNotify=0;reportTime('ended');notify('ended',{});});
 // 500ms 采样：元素没在走就跳过，避免空转发到 Dart。
 setInterval(function(){if(!v.paused)reportTime('tick');},500);
 v.addEventListener('error',function(){if(!booted)return;fail('video element',v.error&&v.error.code);});
 // dash.js 是异步加载的，等它可用再通知 Dart，避免 open 早于库就绪被丢掉。
 // 直播走 hls.js（接口返回的 http_hls 实际是 fmp4 分片，hls.js 用 MSE 解）。
 // 两个库都就绪才算页面可用。
 var dashTimer=setInterval(function(){
  if(window.dashjs&&window.dashjs.MediaPlayer&&window.Hls&&window.Hls.isSupported){
   clearInterval(dashTimer);booted=true;
   notify('log','dash.js + hls.js library ready');
   notify('ready',{});
   if(opened)open(opened);
  }
 },100);
 setTimeout(function(){
  if(!(window.dashjs&&window.dashjs.MediaPlayer)&&!(window.Hls&&window.Hls.isSupported)){
   clearInterval(dashTimer);
   fail('DASH.js load',new Error('player libraries did not become ready'));
  }
 },10000);
})();
</script>
<script>
__DASHJS__
</script>
<script>
__HLSJS__
</script>
</body></html>
''';
    return html
        .replaceFirst('__DASHJS__', dashJsSource)
        .replaceFirst('__HLSJS__', hlsJsSource);
  }

  @override
  Widget build(BuildContext context) {
    final ratio = widget.aspectRatio;
    return ValueListenableBuilder(
      valueListenable: widget.controller.videoSize,
      builder: (context, size, _) {
        final valid = size != null && size.width > 0 && size.height > 0;
        final h = valid ? size.height : 9.0;
        final w = ratio != null && ratio.isFinite && ratio > 0
            ? h * ratio
            : valid
            ? size.width
            : 16.0;
        return Center(
          child: SizedBox(
            width: w,
            height: h,
            child: ColoredBox(
              color: widget.fill,
              child: InAppWebView(
                webViewEnvironment: webViewEnvironment,
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  userAgent: BrowserUa.pc,
                  mediaPlaybackRequiresUserGesture: false,
                  allowsInlineMediaPlayback: true,
                  transparentBackground: false,
                  // 纯渲染用 WebView：关掉缓存、右键菜单和滚动，省掉对应的
                  // 存储与交互开销；页面里没有可滚动内容也不需要手势。
                  cacheEnabled: false,
                  disableContextMenu: true,
                  disableVerticalScroll: true,
                  disableHorizontalScroll: true,
                ),
                initialUrlRequest: URLRequest(
                  url: WebUri(JsWebPlayer.playerPageUrl),
                ),
                onWebViewCreated: (controller) {
                  RuntimeLog.info('WebView created');
                  widget.controller.attachWebView(controller);
                  // 页面只从 callHandler('dashMessage', …) 这一个通道上报。
                  controller.addJavaScriptHandler(
                    handlerName: 'dashMessage',
                    callback: (args) {
                      if (args.isNotEmpty) _onPageMessage(args.first);
                      return null;
                    },
                  );
                },
                shouldInterceptRequest: _intercept,
                onLoadStart: (controller, url) {
                  RuntimeLog.info(
                    'WebView load start ${url?.host ?? 'unknown'} '
                    'loaded=$_pageLoaded',
                  );
                },
                onReceivedError: (controller, request, error) {
                  RuntimeLog.error(
                    'WebView request failed ${request.url.host}',
                    '${error.type}: ${error.description}',
                  );
                },
                onConsoleMessage: (controller, consoleMessage) {
                  RuntimeLog.info(
                    'WebView console ${consoleMessage.messageLevel}: '
                    '${consoleMessage.message}',
                  );
                },
                onLoadStop: (controller, url) {
                  RuntimeLog.info(
                    'WebView load stop ${url?.host ?? 'unknown'} '
                    'loaded=$_pageLoaded',
                  );
                  if (_pageLoaded) return;
                  _pageLoaded = true;
                  // 只等页面本身加载完；dash.js 是内联解析的，就绪由后端
                  // reportPageReady 单独上报，不该在这里再套一层超时。
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
