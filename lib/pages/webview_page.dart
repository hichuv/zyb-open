import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/constants.dart';
import '../models/zk_post.dart';
import '../services/api_service.dart';
import '../services/haptic_service.dart';
import '../services/official_api_service.dart';
import '../state/login_state.dart';
import '../theme/app_theme.dart';
import '../widgets/zyb_feedback.dart';

export '../theme/app_theme.dart' show zybHorizontalPageRoute;

class WebViewPage extends StatefulWidget {
  final String url;
  final String? title;
  final List<ZkPost> posts;
  final int initialIndex;
  final bool initialDesktopMode;

  const WebViewPage({
    super.key,
    required this.url,
    this.title,
    this.posts = const [],
    this.initialIndex = -1,
    this.initialDesktopMode = false,
  });

  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> {
  final ApiService _api = ApiService();
  final OfficialApiService _officialApi = OfficialApiService();
  InAppWebViewController? _controller;
  PullToRefreshController? _pullToRefreshController;
  double _progress = 0;
  bool _desktopMode = false;
  bool _switcherVisible = true;
  bool _loginDetected = false;
  bool _ratingHistoryDirty = false;
  bool _isFavorited = false;
  String _favId = '';
  int _lastAutoLoadMoreSetupQueuedAt = 0;
  late String _currentUrl;
  late String _currentTitle;
  late int _currentIndex;
  String? _entryTid;
  String? _lastReplyReturnUrl;
  String? _lastReplyTargetPid;
  bool _replySubmitPending = false;
  bool _replyHistoryDirty = false;
  bool _replyReturnInProgress = false;
  bool _pendingReplyScroll = false;

  final List<Timer> _activeTimers = [];

  void _registerTimer(Timer timer) {
    _activeTimers.removeWhere((t) => !t.isActive);
    _activeTimers.add(timer);
  }

  void _cancelAllTimers() {
    for (final timer in _activeTimers) {
      timer.cancel();
    }
    _activeTimers.clear();
  }

  @override
  void dispose() {
    _cancelAllTimers();
    _pullToRefreshController?.dispose();
    _controller = null;
    FocusManager.instance.primaryFocus?.unfocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.url;
    _currentTitle = widget.title ?? '';
    _currentIndex = widget.initialIndex;
    _desktopMode = widget.initialDesktopMode;
    _entryTid = _tidOf(widget.url);

    _pullToRefreshController = kIsWeb
        ? null
        : PullToRefreshController(
            settings: PullToRefreshSettings(
              color: ZybColors.light.primary,
            ),
            onRefresh: () async {
              HapticService.instance.lightImpact();
              if (defaultTargetPlatform == TargetPlatform.android) {
                await _controller?.reload();
              } else if (defaultTargetPlatform == TargetPlatform.iOS) {
                await _controller?.loadUrl(
                  urlRequest: URLRequest(url: await _controller?.getUrl()),
                );
              }
            },
          );
    _checkFavoriteState();
  }

  Future<void> _checkFavoriteState() async {
    final tid = _entryTid ?? _tidOf(_currentUrl);
    if (tid == null || tid.isEmpty) {
      if (mounted) setState(() => _isFavorited = false);
      return;
    }
    try {
      final detail = await _officialApi.fetchThread(tid: tid, page: 1);
      if (mounted) {
        setState(() {
          _isFavorited = detail.favorite;
          _favId = detail.favId;
        });
      }
    } catch (_) {}
  }

  Future<void> _toggleFavorite() async {
    final tid = _entryTid ?? _tidOf(_currentUrl);
    if (tid == null || tid.isEmpty) return;
    HapticService.instance.lightImpact();
    final target = !_isFavorited;
    setState(() => _isFavorited = target);
    try {
      if (target) {
        final favId = await _officialApi.favoriteThread(tid);
        if (favId.isNotEmpty) _favId = favId;
        if (!mounted) return;
        _toast('收藏成功');
      } else {
        await _officialApi.unfavoriteThread(favId: _favId, tid: tid);
        _favId = '';
        if (!mounted) return;
        _toast('已取消收藏');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isFavorited = !target);
        _toast(target ? '收藏失败' : '取消收藏失败');
      }
    }
  }

  String _mobileUrl(String url) {
    var next = url.replaceAll(RegExp(r'([?&])mobile=no&?'), r'$1');
    next = next.replaceAll(RegExp(r'[?&]$'), '');
    return mobileUrl(next);
  }

  String _effectiveUrl(String url) =>
      _desktopMode ? _desktopUrl(url) : _mobileUrl(url);

  String _desktopUrl(String url) {
    var next = url.replaceAll(RegExp(r'([?&])mobile=2&?'), r'$1');
    next = next.replaceAll(RegExp(r'[?&]$'), '');
    if (!next.contains('zuanke8.com')) return next;
    final separator = next.contains('?') ? '&' : '?';
    return '$next${separator}mobile=no';
  }

  InAppWebViewSettings _settings() {
    return InAppWebViewSettings(
      useHybridComposition: true,
      userAgent: _desktopMode ? userAgent : mobileUserAgent,
      preferredContentMode: _desktopMode
          ? UserPreferredContentMode.DESKTOP
          : UserPreferredContentMode.MOBILE,
      useWideViewPort: _desktopMode,
      loadWithOverviewMode: _desktopMode,
      useShouldOverrideUrlLoading: true,
    );
  }

  Future<void> _reloadCurrent() async {
    _progress = 0;
    await _controller?.loadUrl(
      urlRequest: URLRequest(url: WebUri(_effectiveUrl(_currentUrl))),
    );
  }

  Future<void> _refreshCurrent() async {
    await _reloadCurrent();
    _toast('刷新成功');
  }

  Future<void> _toggleDesktopMode() async {
    setState(() => _desktopMode = !_desktopMode);
    await _controller?.setSettings(settings: _settings());
    await _reloadCurrent();
    _toast(_desktopMode ? '已切换电脑版' : '已切换手机版');
  }

  Future<void> _hideJdAd() async {
    if (_desktopMode) return;
    const script = r'''
(function() {
  function hideNode(node) {
    if (!node) return;
    node.style.setProperty('display', 'none', 'important');
  }
  var all = Array.prototype.slice.call(document.querySelectorAll('body *'));
  all.forEach(function(el) {
    var text = (el.innerText || el.textContent || '').replace(/\s+/g, '');
    if (text.indexOf('每天领取京东618红包') !== -1) {
      hideNode(el);
      var p = el.parentElement;
      var pt = p ? (p.innerText || p.textContent || '').replace(/\s+/g, '') : '';
      var rect = p && p.getBoundingClientRect ? p.getBoundingClientRect() : {height: 999};
      if (p && pt.indexOf('每天领取京东618红包') !== -1 && pt.length < 80 && rect.height < 80) {
        hideNode(p);
      }
    }
  });
})();
''';
    await _controller?.evaluateJavascript(source: script);
    _registerTimer(Timer(const Duration(milliseconds: 500), () {
      if (mounted) _controller?.evaluateJavascript(source: script);
    }));
    _registerTimer(Timer(const Duration(milliseconds: 1500), () {
      if (mounted) _controller?.evaluateJavascript(source: script);
    }));
  }

  Future<void> _setupAutoLoadMore() async {
    if (_desktopMode) return;
    const script = r'''
(function() {
  if (window.__zybAutoLoadMoreInstalled) return;
  window.__zybAutoLoadMoreInstalled = true;
  window.__zybAutoLoadMoreBusy = false;
  window.__zybAutoLoadMoreLastClick = 0;
  window.__zybAutoLoadMoreSeenKey = '';
  window.__zybAutoLoadMoreSeenAt = 0;
  window.__zybAutoLoadMorePendingTimer = 0;

  var moreTextRe = /\u52a0\u8f7d\u66f4\u591a|\u70b9\u51fb\u52a0\u8f7d\u66f4\u591a|\u67e5\u770b\u66f4\u591a|\u66f4\u591a\u56de\u590d|\u66f4\u591a\u8bc4\u8bba/;
  var loadingTextRe = /\u52a0\u8f7d\u4e2d|\u6b63\u5728\u52a0\u8f7d|\u8bf7\u7a0d\u5019|\u7a0d\u5019/;

  function pageHeight() {
    var doc = document.documentElement;
    var body = document.body;
    return Math.max(doc.scrollHeight || 0, body ? body.scrollHeight || 0 : 0);
  }
  function postCount() {
    return document.querySelectorAll('[id^="pid"], [id^="post_"], .plc').length;
  }
  function changedFrom(snapshot) {
    return pageHeight() > snapshot.height + 40 ||
        postCount() > snapshot.count ||
        buttonKey(findMoreButton()) !== snapshot.key;
  }
  function visible(el) {
    if (!el) return false;
    var style = window.getComputedStyle(el);
    if (!style || style.display === 'none' || style.visibility === 'hidden' || parseFloat(style.opacity || '1') === 0) return false;
    var rect = el.getBoundingClientRect();
    return rect.width > 0 && rect.height > 0;
  }
  function textOf(el) {
    return ((el && (el.innerText || el.textContent || el.value)) || '').replace(/\s+/g, '').trim();
  }
  function buttonKey(el) {
    if (!el) return '';
    return el.getAttribute('data-num') || el.getAttribute('href') || textOf(el);
  }
  function ajaxActive() {
    try { return !!(window.jQuery && window.jQuery.active > 0); } catch (e) { return false; }
  }
  function loadingLike(el) {
    if (!el) return false;
    return loadingTextRe.test(textOf(el)) || !!el.disabled || /\bloading\b|\bdisabled\b/.test(String(el.className || ''));
  }
  function findMoreButton() {
    var directHit = Array.prototype.slice.call(document.querySelectorAll('a.morelink[data-num], a.morelink')).find(function(el) {
      return visible(el) && (el.hasAttribute('data-num') || moreTextRe.test(textOf(el)));
    });
    if (directHit) return directHit;
    var textHit = Array.prototype.slice.call(document.querySelectorAll('a,button,[role="button"]')).find(function(el) {
      return visible(el) && moreTextRe.test(textOf(el));
    });
    if (textHit) return textHit;
    var buttons = Array.prototype.slice.call(document.querySelectorAll('a.morelink[data-num], a.morelink'));
    var hit = buttons.find(function(el) {
      return visible(el) && /\u52a0\u8f7d\u66f4\u591a|\u70b9\u51fb\u52a0\u8f7d\u66f4\u591a|\u67e5\u770b\u66f4\u591a|\u66f4\u591a\u56de\u590d/.test(textOf(el));
    });
    if (hit) return hit;
    return Array.prototype.slice.call(document.querySelectorAll('a,button,[role="button"]')).find(function(el) {
      return visible(el) && /\u52a0\u8f7d\u66f4\u591a|\u70b9\u51fb\u52a0\u8f7d\u66f4\u591a|\u67e5\u770b\u66f4\u591a|\u66f4\u591a\u56de\u590d|\u66f4\u591a\u8bc4\u8bba/.test(textOf(el));
    }) || null;
  }
  function shouldTrigger(button) {
    if (!button) return false;
    var rect = button.getBoundingClientRect();
    return rect.top <= window.innerHeight + 520 && rect.bottom >= -260;
  }
  function sameWaitingButton(key) {
    var button = findMoreButton();
    return button && shouldTrigger(button) && buttonKey(button) === key && !loadingLike(button);
  }
  function mouseTap(el) {
    var rect = el.getBoundingClientRect();
    var x = rect.left + Math.max(1, rect.width / 2);
    var y = rect.top + Math.max(1, rect.height / 2);
    var mouseInit = { bubbles: true, cancelable: true, view: window, clientX: x, clientY: y };
    try { el.dispatchEvent(new MouseEvent('mouseover', mouseInit)); } catch (e) {}
    try { el.dispatchEvent(new MouseEvent('mousedown', mouseInit)); } catch (e) {}
    try { el.dispatchEvent(new MouseEvent('mouseup', mouseInit)); } catch (e) {}
    try { el.dispatchEvent(new MouseEvent('click', mouseInit)); } catch (e) {}
    try { el.click(); } catch (e) {}
  }
  function jqueryTap(el) {
    if (!window.jQuery) return;
    try { window.jQuery(el).trigger('click'); } catch (e) {}
  }
  function scheduleTrigger(delay) {
    if (window.__zybAutoLoadMorePendingTimer) return;
    window.__zybAutoLoadMorePendingTimer = setTimeout(function() {
      window.__zybAutoLoadMorePendingTimer = 0;
      triggerLoadMore();
    }, delay);
  }
  function finishAttempt(snapshot, startedAt) {
    if (Date.now() - startedAt < 3600 && (ajaxActive() || loadingLike(findMoreButton()))) {
      setTimeout(function() { finishAttempt(snapshot, startedAt); }, 280);
      return;
    }
    window.__zybAutoLoadMoreBusy = false;
    scheduleTrigger(changedFrom(snapshot) ? 160 : 260);
  }
  function startAttempt(button, key) {
    var snapshot = { height: pageHeight(), count: postCount(), key: key };
    var startedAt = Date.now();
    window.__zybAutoLoadMoreBusy = true;
    window.__zybAutoLoadMoreLastClick = startedAt;
    mouseTap(button);

    setTimeout(function() {
      if (changedFrom(snapshot) || ajaxActive()) return;
      var retryButton = findMoreButton();
      if (sameWaitingButton(key) && retryButton) jqueryTap(retryButton);
    }, 300);

    setTimeout(function() {
      if (changedFrom(snapshot) || ajaxActive()) return;
      var retryButton = findMoreButton();
      if (sameWaitingButton(key) && retryButton) mouseTap(retryButton);
    }, 760);

    setTimeout(function() { finishAttempt(snapshot, startedAt); }, 1250);
  }
  function triggerLoadMore() {
    var button = findMoreButton();
    if (!shouldTrigger(button)) return;
    var key = buttonKey(button);
    var now = Date.now();
    if (key !== window.__zybAutoLoadMoreSeenKey) {
      window.__zybAutoLoadMoreSeenKey = key;
      window.__zybAutoLoadMoreSeenAt = now;
      scheduleTrigger(180);
      return;
    }
    var stableFor = now - window.__zybAutoLoadMoreSeenAt;
    if (stableFor < 180) {
      scheduleTrigger(180 - stableFor);
      return;
    }
    if (window.__zybAutoLoadMoreBusy || now - window.__zybAutoLoadMoreLastClick < 680) {
      scheduleTrigger(160);
      return;
    }
    startAttempt(button, key);
  }
  function installObserver() {
    var root = document.body || document.documentElement;
    if (!root || !window.MutationObserver) return;
    try {
      var observer = new MutationObserver(function() { scheduleTrigger(90); });
      observer.observe(root, {
        childList: true,
        subtree: true,
        attributes: true,
        attributeFilter: ['class', 'style', 'data-num']
      });
      window.__zybAutoLoadMoreObserver = observer;
    } catch (e) {}
  }
  window.__zybAutoLoadMoreInterval = setInterval(function() { scheduleTrigger(0); }, 350);
  window.addEventListener('scroll', function() { scheduleTrigger(70); }, { passive: true });
  window.addEventListener('touchmove', function() { scheduleTrigger(90); }, { passive: true });
  window.addEventListener('touchend', function() { scheduleTrigger(70); }, { passive: true });
  window.addEventListener('resize', function() { scheduleTrigger(120); }, { passive: true });
  window.addEventListener('pageshow', function() { scheduleTrigger(180); }, { passive: true });
  document.addEventListener('DOMContentLoaded', function() { scheduleTrigger(180); }, { passive: true });
  installObserver();
  scheduleTrigger(280);
  setTimeout(function() { scheduleTrigger(0); }, 900);
  setTimeout(function() { scheduleTrigger(0); }, 1600);
})();
''';
    await _controller?.evaluateJavascript(source: script);
  }

  Future<void> _trySetupAutoLoadMore() async {
    if (_desktopMode || _controller == null) return;
    try {
      await _setupAutoLoadMore();
    } catch (_) {
      // The page may not have a JavaScript context yet; later scheduled attempts will retry.
    }
  }

  void _queueAutoLoadMoreSetup([int delayMs = 0]) {
    if (_desktopMode) return;
    if (delayMs == 0) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastAutoLoadMoreSetupQueuedAt < 180) return;
      _lastAutoLoadMoreSetupQueuedAt = now;
    }
    _registerTimer(Timer(Duration(milliseconds: delayMs), () {
      if (!mounted || _desktopMode) return;
      _trySetupAutoLoadMore();
    }));
  }

  void _queueAutoLoadMoreSetupBurst() {
    for (final delayMs in <int>[120, 350, 800, 1500, 2600, 4200]) {
      _queueAutoLoadMoreSetup(delayMs);
    }
  }

  Future<void> _setupRatingBackGuard() async {
    if (_desktopMode) return;
    const script = r'''
(function() {
  if (window.__zybRatingBackGuardInstalled) return;
  window.__zybRatingBackGuardInstalled = true;
  function mark() {
    window.__zybRatingTouchedAt = Date.now();
    try {
      if (window.flutter_inappwebview) window.flutter_inappwebview.callHandler('zybRatingTouched');
    } catch (e) {}
  }
  function looksLikeRate(el) {
    while (el && el !== document.body) {
      var text = ((el.innerText || el.textContent || el.value || '') + '').replace(/\s+/g, '');
      var href = ((el.href || el.getAttribute && el.getAttribute('href') || '') + '').toLowerCase();
      var onclick = ((el.getAttribute && el.getAttribute('onclick') || '') + '').toLowerCase();
      if (/\u52a0\u679c|\u8bc4\u5206|\u7ed9\u5206|\u679c\u679c/.test(text) || href.indexOf('action=rate') !== -1 || onclick.indexOf('rate') !== -1) return true;
      el = el.parentElement;
    }
    return false;
  }
  document.addEventListener('click', function(e) {
    if (looksLikeRate(e.target)) mark();
  }, true);
})();
''';
    await _controller?.evaluateJavascript(source: script);
  }

  Future<void> _setupReplyBackGuard() async {
    if (_desktopMode) return;
    const script = r'''
(function() {
  if (window.__zybReplyBackGuardInstalled) return;
  window.__zybReplyBackGuardInstalled = true;
  window.__zybReplyLastPid = window.__zybReplyLastPid || '';
  window.__zybReplyLastThreadUrl = window.__zybReplyLastThreadUrl || '';
  window.__zybReplySuccessSent = false;

  function abs(url) {
    try { return new URL(String(url || ''), location.href).href; } catch (e) { return String(url || ''); }
  }
  function param(name, url) {
    var source = String(url || '');
    try {
      var match = new RegExp('[?&]' + name + '=([^&#]*)', 'i').exec(source);
      return match ? decodeURIComponent(match[1].replace(/\+/g, ' ')) : '';
    } catch (e) { return ''; }
  }
  function ensureMobile(url) {
    if (!url) return '';
    if (/[?&]mobile=/i.test(url)) return url;
    return url + (url.indexOf('?') === -1 ? '?' : '&') + 'mobile=2';
  }
  function tidFrom(url) {
    var source = abs(url || location.href);
    var tid = param('tid', source) || param('ptid', source);
    var rewrite = /(?:^|\/)thread-(\d+)-/i.exec(source);
    return tid || (rewrite ? rewrite[1] : '');
  }
  function threadUrlFrom(url) {
    var source = abs(url || location.href);
    var tid = tidFrom(source);
    if (!tid) return '';
    if (/mod=viewthread/i.test(source) || /(?:^|\/)thread-\d+-/i.test(source)) {
      return ensureMobile(source);
    }
    return ensureMobile('http://www.zuanke8.com/forum.php?mod=viewthread&tid=' + tid);
  }
  function textOf(el) {
    return ((el && (el.innerText || el.textContent || el.value || el.title || el.getAttribute && el.getAttribute('aria-label'))) || '').replace(/\s+/g, '').trim();
  }
  function pidFromString(value) {
    var source = String(value || '');
    return param('repquote', source) || param('pid', source) || ((/(?:pid|post_|repquote)[=:'"_\-]*(\d+)/i.exec(source) || [])[1] || '');
  }
  function pidFromElement(el) {
    var node = el;
    for (var i = 0; node && i < 10; i++, node = node.parentElement) {
      var id = String(node.id || '');
      var idHit = /^(?:pid|post_)(\d+)$/i.exec(id) || /(?:pid|post_)(\d+)/i.exec(id);
      if (idHit) return idHit[1];
      var dataPid = node.getAttribute && (node.getAttribute('data-pid') || node.getAttribute('pid'));
      if (dataPid && /\d+/.test(dataPid)) return (/\d+/.exec(dataPid) || [])[0];
      var href = node.href || (node.getAttribute && node.getAttribute('href')) || '';
      var onclick = (node.getAttribute && node.getAttribute('onclick')) || '';
      var fromHref = pidFromString(href) || pidFromString(onclick);
      if (fromHref) return fromHref;
    }
    return '';
  }
  function closestAction(el) {
    var node = el;
    while (node && node !== document.body) {
      var tag = String(node.tagName || '').toUpperCase();
      if (tag === 'A' || tag === 'BUTTON' || tag === 'INPUT' || (node.getAttribute && node.getAttribute('role') === 'button')) {
        return node;
      }
      node = node.parentElement;
    }
    return null;
  }
  function looksReplyTrigger(el) {
    if (!el) return false;
    var href = String(el.href || (el.getAttribute && el.getAttribute('href')) || '').toLowerCase();
    var onclick = String((el.getAttribute && el.getAttribute('onclick')) || '').toLowerCase();
    var text = textOf(el);
    return href.indexOf('action=reply') !== -1 ||
        href.indexOf('repquote=') !== -1 ||
        onclick.indexOf('reply') !== -1 ||
        onclick.indexOf('repquote') !== -1 ||
        (/(\u56de\u590d|\u5f15\u7528)/.test(text) && (href || onclick));
  }
  function looksSubmit(el) {
    if (!el) return false;
    var value = [
      el.name || '',
      el.id || '',
      el.type || '',
      el.value || '',
      textOf(el),
      (el.getAttribute && el.getAttribute('onclick')) || ''
    ].join(' ').toLowerCase();
    return /replysubmit|fastpostsubmit|postsubmit|submit/.test(value) ||
        /(\u53d1\u5e03|\u53d1\u8868|\u63d0\u4ea4).{0,6}(\u56de\u590d)?/.test(value);
  }
  function formLooksReply(form) {
    if (!form) return false;
    var action = abs(form.action || (form.getAttribute && form.getAttribute('action')) || '');
    var value = [
      action,
      form.id || '',
      form.name || '',
      textOf(form)
    ].join(' ').toLowerCase();
    return value.indexOf('action=reply') !== -1 ||
        value.indexOf('replysubmit') !== -1 ||
        value.indexOf('fastpost') !== -1 ||
        value.indexOf('postsubmit') !== -1 ||
        !!form.querySelector('textarea[name="message"]');
  }
  function send(type, sourceEl, sourceUrl) {
    var pid = pidFromElement(sourceEl) || window.__zybReplyLastPid || pidFromString(sourceUrl);
    var threadUrl = window.__zybReplyLastThreadUrl || threadUrlFrom(location.href) || threadUrlFrom(sourceUrl);
    if (pid) window.__zybReplyLastPid = pid;
    if (threadUrl) window.__zybReplyLastThreadUrl = threadUrl;
    if (type === 'submit') window.__zybReplySuccessSent = false;
    if (type === 'success') {
      if (window.__zybReplySuccessSent) return;
      window.__zybReplySuccessSent = true;
    }
    try {
      if (window.flutter_inappwebview) {
        window.flutter_inappwebview.callHandler('zybReplyEvent', JSON.stringify({
          type: type,
          pid: pid || '',
          threadUrl: threadUrl || '',
          url: location.href,
          sourceUrl: String(sourceUrl || '')
        }));
      }
    } catch (e) {}
  }
  document.addEventListener('click', function(e) {
    var action = closestAction(e.target);
    if (!action) return;
    var sourceUrl = action.href || (action.getAttribute && action.getAttribute('href')) || '';
    if (looksSubmit(action)) {
      var form = action.form || (action.closest && action.closest('form'));
      if (formLooksReply(form)) {
        send('submit', action, form.action || sourceUrl);
        scheduleSuccessScans();
      }
      return;
    }
    if (looksReplyTrigger(action)) send('target', e.target, sourceUrl);
  }, true);
  document.addEventListener('submit', function(e) {
    var form = e.target;
    if (!formLooksReply(form)) return;
    send('submit', form, form.action || '');
    scheduleSuccessScans();
  }, true);
  function scanSuccess() {
    var text = ((document.body && (document.body.innerText || document.body.textContent)) || '').replace(/\s+/g, '');
    if (/(\u56de\u590d|\u53d1\u5e03|\u53d1\u8868|\u64cd\u4f5c).{0,8}\u6210\u529f/.test(text) ||
        text.indexOf('\u73b0\u5728\u5c06\u8f6c\u5165\u4e3b\u9898\u9875') !== -1 ||
        text.indexOf('\u8f6c\u5165\u4e3b\u9898\u9875') !== -1) {
      send('success', document.body, location.href);
    }
  }
  function scheduleSuccessScans() {
    [180, 420, 800, 1300, 2100, 3400, 5200].forEach(function(delay) {
      setTimeout(scanSuccess, delay);
    });
  }
  if (window.MutationObserver) {
    try {
      var observer = new MutationObserver(function() { scanSuccess(); });
      observer.observe(document.documentElement || document.body, {
        childList: true,
        subtree: true,
        characterData: true
      });
      window.__zybReplySuccessObserver = observer;
    } catch (e) {}
  }
  setTimeout(scanSuccess, 120);
  setTimeout(scanSuccess, 800);
})();
''';
    await _controller?.evaluateJavascript(source: script);
  }

  Future<void> _handleReplyEvent(List<dynamic> args) async {
    final data = _decodeJsPayload(args);
    final type = (data['type'] ?? '').toString();
    final pid = _cleanPid(data['pid']?.toString());
    final threadUrl =
        _threadReturnUrlFrom(data['threadUrl']?.toString() ?? '') ??
        _threadReturnUrlFrom(data['url']?.toString() ?? '') ??
        _threadReturnUrlFrom(data['sourceUrl']?.toString() ?? '');

    if (threadUrl != null) _lastReplyReturnUrl = threadUrl;
    if (pid != null) _lastReplyTargetPid = pid;

    if (type == 'submit') {
      _replySubmitPending = true;
      _replyHistoryDirty = true;
      _pendingReplyScroll = true;
      return;
    }

    if (type == 'success') {
      await _returnToThreadAfterReply();
    }
  }

  Future<void> _handleReplyLoadedPage(String url) async {
    if (!_replySubmitPending && !_replyReturnInProgress) return;

    if (_isThreadUrl(url)) {
      _replySubmitPending = false;
      _replyHistoryDirty = true;
      await _scrollToReplyTarget();
      _replyReturnInProgress = false;
      return;
    }

    if (_isReplyPageUrl(url) && await _pageLooksReplySuccess()) {
      await _returnToThreadAfterReply();
    }
  }

  Future<bool> _pageLooksReplySuccess() async {
    final controller = _controller;
    if (controller == null) return false;
    final raw = await controller.evaluateJavascript(
      source: r'''
(function() {
  var text = ((document.body && (document.body.innerText || document.body.textContent)) || '').replace(/\s+/g, '');
  return (/(\u56de\u590d|\u53d1\u5e03|\u53d1\u8868|\u64cd\u4f5c).{0,8}\u6210\u529f/.test(text) ||
      text.indexOf('\u73b0\u5728\u5c06\u8f6c\u5165\u4e3b\u9898\u9875') !== -1 ||
      text.indexOf('\u8f6c\u5165\u4e3b\u9898\u9875') !== -1) ? '1' : '0';
})();
''',
    );
    return raw?.toString() == '1';
  }

  Future<bool> _pageLooksReplyNoise() async {
    final controller = _controller;
    if (controller == null) return false;
    final raw = await controller.evaluateJavascript(
      source: r'''
(function() {
  var href = String(location.href || '').toLowerCase();
  var text = ((document.body && (document.body.innerText || document.body.textContent)) || '').replace(/\s+/g, '');
  var success = /(\u56de\u590d|\u53d1\u5e03|\u53d1\u8868|\u64cd\u4f5c).{0,8}\u6210\u529f/.test(text) ||
      text.indexOf('\u73b0\u5728\u5c06\u8f6c\u5165\u4e3b\u9898\u9875') !== -1 ||
      text.indexOf('\u8f6c\u5165\u4e3b\u9898\u9875') !== -1;
  var replyUrl = (href.indexOf('mod=post') !== -1 && href.indexOf('action=reply') !== -1) ||
      href.indexOf('replysubmit=yes') !== -1 ||
      href.indexOf('repquote=') !== -1;
  var explicitReplyForm = !!document.querySelector('form[action*="action=reply"], form[action*="replysubmit"]');
  var titleText = '';
  var titleNode = document.querySelector('.nvhm + a, .z .reply, .bar-title, h1, h2, .header, .wp');
  if (titleNode) titleText = ((titleNode.innerText || titleNode.textContent) || '').replace(/\s+/g, '');
  var standaloneReply = replyUrl && (explicitReplyForm ||
      titleText.indexOf('\u56de\u590d') !== -1 ||
      text.indexOf('\u56de\u590d:') !== -1);
  return (success || standaloneReply) ? '1' : '0';
})();
''',
    );
    return raw?.toString() == '1';
  }

  Future<void> _returnToThreadAfterReply() async {
    final controller = _controller;
    if (controller == null || _replyReturnInProgress) return;
    final targetUrl = _lastReplyReturnUrl ?? _threadReturnUrlFrom(_currentUrl);
    if (targetUrl == null || targetUrl.isEmpty) return;

    _replyReturnInProgress = true;
    _replySubmitPending = false;
    _replyHistoryDirty = true;
    _pendingReplyScroll = true;

    final currentUrl = await _currentWebViewUrl();
    if (_isThreadUrl(currentUrl) && _tidOf(currentUrl) == _tidOf(targetUrl)) {
      await _scrollToReplyTarget();
      _replyReturnInProgress = false;
      return;
    }

    await controller.loadUrl(urlRequest: URLRequest(url: WebUri(targetUrl)));
    _registerTimer(Timer(const Duration(seconds: 4), () {
      if (mounted) _replyReturnInProgress = false;
    }));
  }

  Future<void> _scrollToReplyTarget() async {
    final controller = _controller;
    if (controller == null || !_pendingReplyScroll) return;
    _pendingReplyScroll = false;
    final pid = _lastReplyTargetPid ?? '';

    String script() {
      return '''
(function(pid) {
  function pageHeight() {
    var doc = document.documentElement;
    var body = document.body;
    return Math.max(doc.scrollHeight || 0, body ? body.scrollHeight || 0 : 0);
  }
  function visible(el) {
    if (!el) return false;
    var rect = el.getBoundingClientRect();
    return rect.width > 0 && rect.height > 0;
  }
  var el = null;
  if (pid) {
    el = document.getElementById('pid' + pid) ||
        document.getElementById('post_' + pid) ||
        document.querySelector('[data-pid="' + pid + '"]');
  }
  if (!visible(el)) {
    var posts = Array.prototype.slice.call(document.querySelectorAll('[id^="pid"], [id^="post_"], .plc, .message, .t_f'));
    el = posts.length ? posts[posts.length - 1] : null;
  }
  if (visible(el)) {
    var y = el.getBoundingClientRect().top + (window.pageYOffset || document.documentElement.scrollTop || 0) - 88;
    window.scrollTo(0, Math.max(0, y));
    return 'target';
  }
  window.scrollTo(0, pageHeight());
  return 'bottom';
})(${jsonEncode(pid)});
''';
    }

    await controller.evaluateJavascript(source: script());
    for (final delayMs in const <int>[450, 1100, 1900]) {
      _registerTimer(Timer(Duration(milliseconds: delayMs), () {
        if (!mounted) return;
        _controller?.evaluateJavascript(source: script());
      }));
    }
  }

  Future<String> _skipReplyHistoryNoise(
    InAppWebViewController controller,
  ) async {
    var url = (await controller.getUrl())?.toString() ?? '';
    for (var i = 0; i < 5; i++) {
      final isNoise = _isReplyPageUrl(url) || await _pageLooksReplyNoise();
      if (!isNoise) return url;
      if (!(await controller.canGoBack())) {
        await _returnToThreadAfterReply();
        return '';
      }
      await controller.goBack();
      await Future.delayed(const Duration(milliseconds: 260));
      url = (await controller.getUrl())?.toString() ?? '';
    }
    return url;
  }

  Future<bool> _ratingTouchedInPage() async {
    final controller = _controller;
    if (controller == null) return false;
    final raw = await controller.evaluateJavascript(
      source: 'window.__zybRatingTouchedAt ? "1" : "0";',
    );
    final touched = raw?.toString() == '1';
    if (touched) _ratingHistoryDirty = true;
    return touched;
  }

  Future<bool> _closeRatingOverlayIfNeeded() async {
    final controller = _controller;
    if (controller == null) return false;
    final raw = await controller.evaluateJavascript(
      source: r'''
(function() {
  function visible(el) {
    if (!el) return false;
    var s = window.getComputedStyle(el);
    if (!s || s.display === 'none' || s.visibility === 'hidden' || s.opacity === '0') return false;
    var r = el.getBoundingClientRect();
    return r.width > 0 && r.height > 0;
  }
  var directClose = Array.prototype.slice.call(document.querySelectorAll('.flbc,.flb .close,.fwinmask .close,[id^="fwin_"] .close'))
    .find(visible);
  if (directClose) {
    try { directClose.click(); } catch (e) {}
    return '1';
  }
  var overlays = Array.prototype.slice.call(document.querySelectorAll('.fwinmask,[id^="fwin_"],.floatwrap,.dialog,.modal,.popup'))
    .filter(visible);
  for (var i = 0; i < overlays.length; i++) {
    var nodes = Array.prototype.slice.call(overlays[i].querySelectorAll('a,button,input,[role="button"],.flbc,.close'));
    var close = nodes.find(function(el) {
      if (!visible(el)) return false;
      var text = ((el.innerText || el.textContent || el.value || el.title || el.getAttribute('aria-label') || '') + '').replace(/\s+/g, '');
      var cls = String(el.className || '');
      return /\u5173\u95ed|\u53d6\u6d88|\u00d7|X/.test(text) || /flbc|close/.test(cls);
    });
    if (close) {
      try { close.click(); } catch (e) {}
      return '1';
    }
  }
  return '0';
})();
''',
    );
    return raw?.toString() == '1';
  }

  Future<void> _checkLoginChanged() async {
    if (_loginDetected) return;
    final loggedIn = await _api.isLoggedIn();
    if (!loggedIn) return;
    _loginDetected = true;
    await _api.refreshCookie();
    notifyLoginStateChanged();
  }

  bool _isQqScheme(String url) {
    return url.startsWith('wtloginmqq://') ||
        url.startsWith('mqq://') ||
        url.startsWith('mqqapi://');
  }

  bool _isThreadUrl(String url) {
    if (!url.contains('zuanke8.com')) return false;
    final lower = url.toLowerCase();
    return (lower.contains('mod=viewthread') && _tidOf(url) != null) ||
        RegExp(
          r'(^|/)thread-\d+-\d+-\d+\.html',
          caseSensitive: false,
        ).hasMatch(url);
  }

  String? _tidOf(String url) {
    return RegExp(r'[?&]tid=(\d+)').firstMatch(url)?.group(1) ??
        RegExp(
          r'(^|/)thread-(\d+)-',
          caseSensitive: false,
        ).firstMatch(url)?.group(2);
  }

  bool _isSameEntryTidUrl(String url) {
    final currentTid = _entryTid ?? _tidOf(_currentUrl);
    final nextTid = _tidOf(url);
    return currentTid != null && nextTid != null && currentTid == nextTid;
  }

  bool _isRatingPopupUrl(String url) {
    if (!url.contains('zuanke8.com')) return false;
    final lower = url.toLowerCase();
    return lower.contains('action=rate') ||
        lower.contains('mod=misc') ||
        lower.contains('mod=ajax') ||
        lower.contains('infloat=yes') ||
        lower.contains('handlekey=rate') ||
        lower.contains('ratesubmit=yes') ||
        lower.contains('ac=rate');
  }

  bool _isListLikeUrl(String url) {
    if (!url.contains('zuanke8.com')) return false;
    final lower = url.toLowerCase();
    return lower.contains('mod=forumdisplay') ||
        lower.contains('mod=guide') ||
        lower.contains('search.php') ||
        lower.contains('do=favorite') ||
        lower.contains('do=thread') ||
        RegExp(r'(^|/)forum-\d+-\d+\.html', caseSensitive: false).hasMatch(url);
  }

  String _withMobileMode(String url) {
    return _desktopMode ? _desktopUrl(url) : _mobileUrl(url);
  }

  String? _threadReturnUrlFrom(String url) {
    final value = url.trim();
    if (value.isNotEmpty && _isThreadUrl(value)) {
      return _withMobileMode(value);
    }
    final tid = _tidOf(value) ?? _entryTid ?? _tidOf(_currentUrl);
    if (tid == null) return null;
    return _withMobileMode(threadUrl(tid));
  }

  void _rememberThreadUrl(String url) {
    if (!_isThreadUrl(url)) return;
    _currentUrl = _withMobileMode(url);
    final tid = _tidOf(url);
    if (tid == null) return;
    if (_hasNativePostList) {
      _entryTid ??= tid;
    } else {
      _entryTid = tid;
    }
  }

  String? _cleanPid(String? value) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) return null;
    return RegExp(r'\d+').firstMatch(raw)?.group(0);
  }

  Map<String, dynamic> _decodeJsPayload(List<dynamic> args) {
    if (args.isEmpty) return {};
    final payload = args.first;
    if (payload is Map) return Map<String, dynamic>.from(payload);
    if (payload is String && payload.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(payload);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return {};
  }

  bool _isReplyPageUrl(String url) {
    if (!url.contains('zuanke8.com')) return false;
    final lower = url.toLowerCase();
    return (lower.contains('mod=post') && lower.contains('action=reply')) ||
        lower.contains('replysubmit=yes') ||
        lower.contains('repquote=');
  }

  Future<NavigationActionPolicy> _handleNavigation(
    NavigationAction action,
  ) async {
    final url = action.request.url?.toString() ?? '';
    if (_isQqScheme(url)) {
      if (mounted) _toast('不支持QQ登录');
      return NavigationActionPolicy.CANCEL;
    }

    final uri = action.request.url?.uriValue;
    if (uri != null &&
        uri.scheme.isNotEmpty &&
        uri.scheme != 'http' &&
        uri.scheme != 'https' &&
        uri.scheme != 'about') {
      try {
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      } catch (_) {}
      return NavigationActionPolicy.CANCEL;
    }

    if (_isRatingPopupUrl(url) && _isSameEntryTidUrl(url)) {
      _ratingHistoryDirty = true;
      return NavigationActionPolicy.ALLOW;
    }

    _rememberThreadUrl(url);

    return NavigationActionPolicy.ALLOW;
  }

  Future<void> _copyPostContent() async {
    const script = r'''
(function() {
  function textOf(selectors) {
    for (var i = 0; i < selectors.length; i++) {
      var el = document.querySelector(selectors[i]);
      if (el && (el.innerText || el.textContent || '').trim()) {
        return (el.innerText || el.textContent || '').trim();
      }
    }
    return '';
  }
  function firstNode(selectors) {
    for (var i = 0; i < selectors.length; i++) {
      var el = document.querySelector(selectors[i]);
      if (el) return el;
    }
    return null;
  }
  var title = textOf(['.thread_subject', '#thread_subject', 'h1', '.ts span', '.ts', 'title']);
  if (!title) title = document.title || '';
  var author = textOf(['.authi a', '.pi .authi a', 'a[href*="mod=space&uid="]', '.avatar a']);
  var contentNode = firstNode(['.message', '.t_f', '.pcb', '.postmessage', '.plc .pct', 'article']);
  var content = contentNode ? (contentNode.innerText || contentNode.textContent || '').trim() : '';
  var imageRoot = contentNode || document;
  var images = Array.prototype.slice.call(imageRoot.querySelectorAll('img'))
    .map(function(img) { return img.getAttribute('zoomfile') || img.getAttribute('file') || img.src || ''; })
    .filter(function(src) { return src && src.indexOf('avatar') === -1 && src.indexOf('static/image') === -1; })
    .map(function(src) { return new URL(src, location.href).href; });
  images = Array.prototype.slice.call(new Set(images));
  return JSON.stringify({ title: title, author: author, content: content, images: images, url: location.href });
})();
''';

    final raw = await _controller?.evaluateJavascript(source: script);
    final jsonText = raw?.toString() ?? '';
    Map<String, dynamic> data = {};
    try {
      data = jsonDecode(jsonText) as Map<String, dynamic>;
    } catch (_) {}

    final title = _cleanSingleLine(data['title']?.toString() ?? _currentTitle);
    final author = _cleanSingleLine(data['author']?.toString() ?? '');
    final content = _cleanContent(data['content']?.toString() ?? '');
    final images = (data['images'] is List)
        ? (data['images'] as List)
              .map((e) => e.toString())
              .where((e) => e.isNotEmpty)
              .toList()
        : <String>[];
    final url = _cleanSingleLine(data['url']?.toString() ?? _currentUrl);

    final lines = <String>['标题：$title'];
    if (author.isNotEmpty) lines.add('作者：$author');
    if (content.isNotEmpty) {
      lines
        ..add('')
        ..add('正文：')
        ..add(content);
    }
    if (images.isNotEmpty) {
      lines
        ..add('')
        ..add('图片：')
        ..addAll(images);
    }
    lines
      ..add('')
      ..add('链接：')
      ..add(url);

    await Clipboard.setData(ClipboardData(text: lines.join('\n')));
    _toast('内容已复制');
  }

  String _cleanSingleLine(String value) {
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _cleanContent(String value) {
    final lines = value
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');
    final output = <String>[];
    var blank = false;
    for (final line in lines) {
      final text = line.trim();
      if (text.isEmpty) {
        if (output.isNotEmpty && !blank) {
          output.add('');
          blank = true;
        }
      } else {
        output.add(text);
        blank = false;
      }
    }
    while (output.isNotEmpty && output.last.isEmpty) {
      output.removeLast();
    }
    return output.join('\n');
  }

  void _toast(String msg) {
    showZybFeedback(context, msg);
  }

  Future<String> _currentWebViewUrl() async {
    final controller = _controller;
    if (controller == null) return _currentUrl;
    final url = (await controller.getUrl())?.toString() ?? _currentUrl;
    return _isRatingPopupUrl(url) ? _currentUrl : url;
  }

  bool get _hasNativePostList => widget.posts.isNotEmpty && _currentIndex >= 0;

  Future<bool> _goBackInWebView() async {
    final controller = _controller;
    if (controller == null || !(await controller.canGoBack())) return false;

    final beforeUrl = (await controller.getUrl())?.toString() ?? _currentUrl;
    if (_hasNativePostList && _isThreadUrl(beforeUrl)) return false;

    final beforeWasSameEntry = _isSameEntryTidUrl(beforeUrl);
    if (_hasNativePostList &&
        _ratingHistoryDirty &&
        (beforeWasSameEntry || _isRatingPopupUrl(beforeUrl))) {
      return false;
    }

    final skipReplyDuplicateThread =
        _replyHistoryDirty && _isThreadUrl(beforeUrl);
    await controller.goBack();
    await Future.delayed(const Duration(milliseconds: 260));
    var afterUrl = (await controller.getUrl())?.toString() ?? '';
    var skippedReplyNoise = false;

    if (_isReplyPageUrl(afterUrl) || await _pageLooksReplyNoise()) {
      afterUrl = await _skipReplyHistoryNoise(controller);
      skippedReplyNoise = true;
    }

    if (!_hasNativePostList &&
        (skipReplyDuplicateThread || skippedReplyNoise) &&
        afterUrl.isNotEmpty &&
        _isThreadUrl(afterUrl) &&
        _tidOf(afterUrl) == _tidOf(beforeUrl) &&
        await controller.canGoBack()) {
      await controller.goBack();
      await Future.delayed(const Duration(milliseconds: 260));
      afterUrl = (await controller.getUrl())?.toString() ?? '';
      if (_isReplyPageUrl(afterUrl) || await _pageLooksReplyNoise()) {
        afterUrl = await _skipReplyHistoryNoise(controller);
      }
    }

    if (afterUrl.isNotEmpty && !_isRatingPopupUrl(afterUrl)) {
      if (_isThreadUrl(afterUrl)) {
        _rememberThreadUrl(afterUrl);
      } else {
        _currentUrl = afterUrl;
        if (!_hasNativePostList && _isListLikeUrl(afterUrl)) _entryTid = null;
      }
    }
    return true;
  }

  Future<bool> _handleBackInsidePage() async {
    final currentUrl = await _currentWebViewUrl();
    if (await _ratingTouchedInPage() && await _closeRatingOverlayIfNeeded()) {
      return true;
    }
    if (_isReplyPageUrl(currentUrl) || await _pageLooksReplyNoise()) {
      if (await _pageLooksReplySuccess()) {
        await _returnToThreadAfterReply();
        return true;
      }
      if (await _goBackInWebView()) return true;
      await _returnToThreadAfterReply();
      return true;
    }
    if (_hasNativePostList && _isThreadUrl(currentUrl)) return false;
    if (await _goBackInWebView()) return true;
    return false;
  }

  void _handleAppBack() async {
    final handled = await _handleBackInsidePage();
    if (!handled && mounted) {
      Navigator.pop(context);
    }
  }

  void _openPostAtIndex(int index, {required bool fromLeft}) {
    if (index < 0 || index >= widget.posts.length) return;
    final post = widget.posts[index];
    Navigator.push(
      context,
      zybHorizontalPageRoute<void>(
        fromLeft: fromLeft,
        builder: (_) => WebViewPage(
          url: post.url,
          title: post.title,
          posts: widget.posts,
          initialIndex: index,
        ),
      ),
    );
  }

  void _goHome() {
    switchRootTab(0);
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final colors = zybColors(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final handled = await _handleBackInsidePage();
        if (!handled && mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: colors.surface,
          foregroundColor: colors.textPrimary,
          leading: IconButton(
            tooltip: '返回',
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: _handleAppBack,
          ),
          titleSpacing: 0,
          title: const SizedBox.shrink(),
          actions: [
            IconButton(
              tooltip: '首页',
              onPressed: _goHome,
              icon: const Icon(Icons.home_rounded, size: 21),
            ),
            if (widget.posts.isNotEmpty && _currentIndex >= 0)
              IconButton(
                tooltip: _switcherVisible ? '隐藏上下篇' : '显示上下篇',
                onPressed: () {
                  setState(() => _switcherVisible = !_switcherVisible);
                },
                icon: Icon(
                  Icons.swap_vert_rounded,
                  size: 23,
                  color: _switcherVisible
                      ? colors.primary
                      : colors.textSecondary,
                ),
              ),
            if ((_entryTid ?? _tidOf(_currentUrl)) != null)
              IconButton(
                tooltip: _isFavorited ? '取消收藏' : '收藏本帖',
                onPressed: _toggleFavorite,
                icon: Icon(
                  _isFavorited ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: 22,
                  color: _isFavorited ? colors.primary : colors.textSecondary,
                ),
              ),
            IconButton(
              tooltip: '刷新本帖',
              onPressed: _refreshCurrent,
              icon: const Icon(Icons.refresh_rounded, size: 22),
            ),
            IconButton(
              tooltip: '复制内容',
              onPressed: _copyPostContent,
              icon: const Icon(Icons.content_copy_rounded, size: 21),
            ),
            IconButton(
              tooltip: '切换电脑版',
              onPressed: _toggleDesktopMode,
              icon: Icon(
                Icons.desktop_windows_rounded,
                size: 21,
                color: _desktopMode ? colors.primary : colors.textSecondary,
              ),
            ),
            const SizedBox(width: 4),
          ],
          bottom: _progress < 1.0
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(3),
                  child: LinearProgressIndicator(
                    value: _progress,
                    color: colors.primary,
                    backgroundColor: colors.primarySoft,
                  ),
                )
              : null,
        ),
        body: Stack(
          children: [
            InAppWebView(
              initialUrlRequest: URLRequest(
                url: WebUri(_effectiveUrl(_currentUrl)),
              ),
              initialSettings: _settings(),
              pullToRefreshController: _pullToRefreshController,
              onWebViewCreated: (controller) {
                _controller = controller;
                controller.addJavaScriptHandler(
                  handlerName: 'zybRatingTouched',
                  callback: (_) async {
                    _ratingHistoryDirty = true;
                    return null;
                  },
                );
                controller.addJavaScriptHandler(
                  handlerName: 'zybReplyEvent',
                  callback: (args) async {
                    await _handleReplyEvent(args);
                    return null;
                  },
                );
                _queueAutoLoadMoreSetupBurst();
              },
              onTitleChanged: (controller, title) {
                if (title != null &&
                    title.isNotEmpty &&
                    _currentTitle.isEmpty) {
                  setState(() => _currentTitle = title);
                }
              },
              onLoadStart: (controller, url) {
                _queueAutoLoadMoreSetupBurst();
              },
              onLoadStop: (controller, url) async {
                _pullToRefreshController?.endRefreshing();
                _checkFavoriteState();
                final nextUrl = url?.toString();
                if (nextUrl != null && nextUrl.isNotEmpty) {
                  if (_isThreadUrl(nextUrl)) _rememberThreadUrl(nextUrl);
                  if (_isRatingPopupUrl(nextUrl)) {
                    _ratingHistoryDirty = true;
                  } else if (!_isThreadUrl(nextUrl)) {
                    _currentUrl = nextUrl;
                    if (!_hasNativePostList && _isListLikeUrl(nextUrl)) {
                      _entryTid = null;
                    }
                  }
                }
                await _hideJdAd();
                await _setupAutoLoadMore();
                await _setupRatingBackGuard();
                await _setupReplyBackGuard();
                await _handleReplyLoadedPage(nextUrl ?? _currentUrl);
                await _checkLoginChanged();
              },
              onProgressChanged: (controller, progress) {
                setState(() => _progress = progress / 100);
                if (progress >= 100) {
                  _pullToRefreshController?.endRefreshing();
                }
                if (progress >= 10 && progress < 100) {
                  _queueAutoLoadMoreSetup();
                }
              },
              onReceivedError: (controller, request, error) {
                _pullToRefreshController?.endRefreshing();
              },
              onReceivedHttpError: (controller, request, errorResponse) {
                _pullToRefreshController?.endRefreshing();
              },
              onScrollChanged: (controller, x, y) {
                _queueAutoLoadMoreSetup();
              },
              shouldOverrideUrlLoading: (controller, navigationAction) {
                return _handleNavigation(navigationAction);
              },
            ),
            if (widget.posts.isNotEmpty &&
                _currentIndex >= 0 &&
                _switcherVisible)
              Positioned.fill(
                child: _PostSwitcher(
                  onPrev: () {
                    if (_currentIndex <= 0) {
                      _toast('已经是第一篇');
                      return;
                    }
                    _openPostAtIndex(_currentIndex - 1, fromLeft: true);
                  },
                  onNext: () {
                    if (_currentIndex >= widget.posts.length - 1) {
                      _toast('已经是最后一篇');
                      return;
                    }
                    _openPostAtIndex(_currentIndex + 1, fromLeft: false);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PostSwitcher extends StatefulWidget {
  final VoidCallback onPrev;
  final VoidCallback onNext;

  const _PostSwitcher({required this.onPrev, required this.onNext});

  @override
  State<_PostSwitcher> createState() => _PostSwitcherState();
}

class _PostSwitcherState extends State<_PostSwitcher> {
  Offset? _offset;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const width = 48.0;
        const height = 104.0;
        final defaultOffset = Offset(
          constraints.maxWidth - width - 18,
          constraints.maxHeight - height - 88,
        );
        final current = _offset ?? defaultOffset;
        final left = current.dx.clamp(8.0, constraints.maxWidth - width - 8);
        final top = current.dy.clamp(8.0, constraints.maxHeight - height - 8);
        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onPanUpdate: (details) {
                  setState(() => _offset = Offset(left, top) + details.delta);
                },
                child: _SwitcherButtons(
                  onPrev: widget.onPrev,
                  onNext: widget.onNext,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SwitcherButtons extends StatelessWidget {
  final VoidCallback onPrev;
  final VoidCallback onNext;

  const _SwitcherButtons({required this.onPrev, required this.onNext});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 104,
      child: Column(
        children: [
          _SwitcherArrow(icon: Icons.keyboard_arrow_up_rounded, onTap: onPrev),
          const SizedBox(height: 8),
          _SwitcherArrow(
            icon: Icons.keyboard_arrow_down_rounded,
            onTap: onNext,
          ),
        ],
      ),
    );
  }
}

class _SwitcherArrow extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _SwitcherArrow({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = zybColors(context);
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.primarySoft,
            border: Border.all(
              color: colors.primary.withValues(alpha: 0.28),
              width: 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: colors.shadow,
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Icon(icon, color: colors.primary, size: 34),
        ),
      ),
    );
  }
}
