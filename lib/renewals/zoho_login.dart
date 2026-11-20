import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../app_theme.dart';
import 'zoho_vault.dart';

/// A small browser inside HQ, only for Zoho Mail.
/// Zoho clears a free mailbox after 120 days without a login, so: open Zoho → you sign in →
/// as soon as the Zoho Mail inbox opens, HQ marks that mailbox "logged in today".
///
/// If you saved the mailbox's password (Renewals → Email → Set password, kept in the Keychain),
/// HQ fills Zoho's sign-in page: email → Next → password → Sign in. A 2-step code you type yourself.
/// No password saved → HQ fills only the email address and you type the password.
/// HQ reads nothing back from the page; it only watches the address to see when the inbox opens.
/// Cookies are cleared before and after, so every visit is a real, fresh login and accounts don't mix.
class ZohoLogin extends StatefulWidget {
  const ZohoLogin({super.key, required this.address});
  final String address; // e.g. hello@quvlet.com — shown so you sign in to the right one

  /// Opens the browser. Returns true when the Zoho Mail inbox was reached.
  static Future<bool> open(BuildContext context, String address) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ZohoLogin(address: address),
    );
    return ok == true;
  }

  /// The inbox: mail.zoho.<any data centre>/zm/…
  static bool isInbox(String url) {
    final u = Uri.tryParse(url);
    if (u == null) return false;
    return RegExp(r'^mail\.zoho\.[a-z.]+$').hasMatch(u.host) && u.path.startsWith('/zm');
  }

  @override
  State<ZohoLogin> createState() => _ZohoLoginState();
}

class _ZohoLoginState extends State<ZohoLogin> {
  static const _start = 'https://accounts.zoho.com/signin?servicename=VirtualOffice&serviceurl=https%3A%2F%2Fmail.zoho.com%2Fzm%2F';
  WebViewController? _web;
  String _url = '';
  bool _done = false;
  String? _password; // from the Keychain, in memory only while this window is open
  Timer? _fill;
  int _tries = 0;

  /// Fills Zoho's sign-in page (#login_id → #nextbtn, then #password → #nextbtn). Each step once.
  /// Values go in through jsonEncode, so nothing in them can run as code.
  static const _fillJs = r'''
(function(e, p) {
  function vis(el) { return el && el.offsetParent !== null; }
  function setv(el, v) {
    var s = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
    s.call(el, v);
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
  }
  var id = document.getElementById('login_id'), pw = document.getElementById('password'),
      btn = document.getElementById('nextbtn');
  if (p && vis(pw) && !window.__hqPw) { setv(pw, p); window.__hqPw = 1; if (btn) setTimeout(function () { btn.click(); }, 400); return; }
  if (vis(id) && !window.__hqId) { setv(id, e); window.__hqId = 1; if (btn) setTimeout(function () { btn.click(); }, 400); }
})(%E%, %P%);
''';

  void _startFilling() {
    _fill?.cancel();
    _tries = 0;
    _fill = Timer.periodic(const Duration(seconds: 1), (t) async {
      final host = Uri.tryParse(_url)?.host ?? '';
      if (_done || ++_tries > 90 || !mounted) return t.cancel();
      if (!host.startsWith('accounts.zoho.')) return;
      final js = _fillJs
          .replaceFirst('%E%', jsonEncode(widget.address))
          .replaceFirst('%P%', jsonEncode(_password ?? ''));
      try {
        await _web?.runJavaScript(js);
      } catch (_) {} // page changed under us — next tick tries again
    });
  }

  @override
  void initState() {
    super.initState();
    _begin();
  }

  Future<void> _begin() async {
    await WebViewCookieManager().clearCookies(); // fresh login, nobody else's session
    _password = await ZohoVault.passwordFor(widget.address);
    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted) // Zoho's sign-in page needs it
      ..setNavigationDelegate(NavigationDelegate(
        onUrlChange: (ch) => _seen(ch.url ?? ''),
        onPageFinished: _seen,
      ))
      ..loadRequest(Uri.parse(_start));
    if (mounted) setState(() => _web = c);
    _startFilling();
  }

  void _seen(String url) {
    if (!mounted) return;
    setState(() => _url = url);
    if (!_done && ZohoLogin.isInbox(url)) {
      _done = true;
      Future.delayed(const Duration(seconds: 2), _close); // let the inbox load = counts as a visit
    }
  }

  @override
  void dispose() {
    _fill?.cancel();
    _password = null;
    super.dispose();
  }

  Future<void> _close() async {
    _fill?.cancel();
    await WebViewCookieManager().clearCookies(); // sign out of this mailbox inside HQ
    if (mounted) Navigator.of(context).pop(_done);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(40),
      child: SizedBox(
        width: 980,
        height: 720,
        child: Column(children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            color: _done ? HqColors.good.withValues(alpha: 0.12) : null,
            child: Row(children: [
              Expanded(
                child: Text(
                  _done
                      ? '✓ ${widget.address} — inbox opened. Marking it logged in today…'
                      : _password == null
                          ? 'Sign in to Zoho as  ${widget.address}  — type the password (none saved). HQ ticks it when the inbox opens.'
                          : 'Signing in to Zoho as  ${widget.address}  with the saved password… (type any 2-step code yourself)',
                  style: jost(14, weight: 600, color: _done ? HqColors.good : HqColors.ink),
                ),
              ),
              TextButton(onPressed: _close, child: Text(_done ? 'Done' : 'Cancel')),
            ]),
          ),
          const Divider(height: 1),
          Expanded(child: _web == null ? const Center(child: CircularProgressIndicator()) : WebViewWidget(controller: _web!)),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Text(Uri.tryParse(_url)?.host ?? '', style: jost(11, color: HqColors.muted)),
          ),
        ]),
      ),
    );
  }
}
