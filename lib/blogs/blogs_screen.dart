import 'dart:io';

import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import '../actions/action_log.dart';
import '../app_theme.dart';
import '../widgets/format.dart';
import '../widgets/screen_frame.dart';
import 'blog_api.dart';

/// Blogs: write, publish and remove posts on the 5 blogs (intoGEMOLOGY, gemstok.com, ManiKVault, Quvlet,
/// Gemmit) — the same thing internal.gemstok.com/blog.html does, from HQ.
/// Every change: a confirm screen that says exactly what happens → Touch ID → a line in the HQ action log.
class BlogsScreen extends StatefulWidget {
  const BlogsScreen({super.key});

  @override
  State<BlogsScreen> createState() => _BlogsScreenState();
}

class _BlogsScreenState extends State<BlogsScreen> {
  BlogSite _blog = BlogSite.all.first;
  List<Map<String, dynamic>>? _posts;
  String? _error;
  String? _info;
  bool _busy = false;

  // editor
  bool _editing = false;
  Map<String, dynamic>? _post; // null = new post
  final _title = TextEditingController();
  final _slug = TextEditingController();
  final _category = TextEditingController();
  final _dailyGem = TextEditingController();
  final _image = TextEditingController();
  final _content = TextEditingController();
  bool _published = true;
  String? _editorError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_title, _slug, _category, _dailyGem, _image, _content]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _posts = null;
      _error = null;
    });
    try {
      final p = await BlogApi.posts(_blog);
      if (mounted) setState(() => _posts = p);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  void _open(BlogSite b) {
    setState(() {
      _blog = b;
      _editing = false;
      _info = null;
    });
    _load();
  }

  // ------------------------------------------------------------------ the guard every change goes through

  /// Confirm screen (what exactly happens) → Touch ID → run → action log. true = done.
  Future<bool> _guarded(String title, List<String> what, String action, Map<String, Object?> details,
      Future<void> Function() run) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: jost(18, weight: 600)),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final w in what)
              Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('• $w', style: jost(14))),
            const SizedBox(height: 6),
            Text('Touch ID comes next. This is written to the HQ action log.', style: jost(12, color: HqColors.muted)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continue')),
        ],
      ),
    );
    if (ok != true) return false;
    var touched = false;
    try {
      touched = await LocalAuthentication().authenticate(localizedReason: title.toLowerCase());
    } catch (_) {}
    if (!touched) {
      if (mounted) setState(() => _error = 'Touch ID not confirmed — nothing changed.');
      return false;
    }
    setState(() => _busy = true);
    try {
      await run();
      await ActionLog.write(action, details, ok: true);
      return true;
    } catch (e) {
      await ActionLog.write(action, details, ok: false, error: '$e');
      if (mounted) setState(() => _error = '$e');
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ------------------------------------------------------------------ editor

  void _edit(Map<String, dynamic>? p) {
    setState(() {
      _editing = true;
      _post = p;
      _title.text = '${p?['title'] ?? ''}';
      _slug.text = '${p?['slug'] ?? ''}';
      _category.text = '${p?['category'] ?? ''}';
      _dailyGem.text = '${p?['daily_gem'] ?? ''}';
      _image.text = '${p?['featured_image'] ?? ''}';
      _content.text = '${p?['content'] ?? ''}';
      _published = p == null ? true : p['published_at'] != null;
      _editorError = null;
      _info = null;
    });
  }

  Future<void> _pickImage() async {
    // the macOS file chooser, pictures only
    final r = await Process.run('osascript',
        ['-e', 'POSIX path of (choose file with prompt "Picture for the blog post" of type {"public.image"})']);
    final path = '${r.stdout}'.trim();
    if (r.exitCode != 0 || path.isEmpty) return; // cancelled
    final f = File(path);
    String? url;
    final done = await _guarded(
      'Upload picture',
      ['Uploads ${f.uri.pathSegments.last} to the shared blog-images storage (anyone with the link can see it).',
        'Its link goes into "Featured image".'],
      'blog.upload_image',
      {'blog': _blog.id, 'file': f.uri.pathSegments.last},
      () async => url = await BlogApi.uploadImage(_blog, f),
    );
    if (done && url != null && mounted) setState(() => _image.text = url!);
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    final slug = BlogApi.slugify(_slug.text.isEmpty ? title : _slug.text);
    if (title.isEmpty || slug.isEmpty) {
      setState(() => _editorError = 'Title and slug are required.');
      return;
    }
    final p = _post;
    final wasPublished = p?['published_at'] != null;
    final rec = <String, dynamic>{
      'title': title,
      'slug': slug,
      'category': _category.text.trim().isEmpty ? null : _category.text.trim(),
      'featured_image': _image.text.trim().isEmpty ? null : _image.text.trim(),
      'content': _content.text,
      // keep the first publish date when an already-published post is edited
      'published_at': _published ? (p?['published_at'] ?? DateTime.now().toUtc().toIso8601String()) : null,
      if (_blog.dailyGem) 'daily_gem': _dailyGem.text.trim().isEmpty ? null : _dailyGem.text.trim(),
    };
    final what = <String>[
      if (p == null) 'Creates a new post on ${_blog.label}: "$title".' else 'Saves your changes to "$title" on ${_blog.label}.',
      if (_published && !wasPublished) 'PUBLISHES it now — it shows on ${_blog.site.replaceFirst('https://', '')} straight away.',
      if (_published && wasPublished) 'It stays published (first published ${fmtDate(DateTime.tryParse('${p!['published_at']}'))}).',
      if (!_published && wasPublished) 'UNPUBLISHES it — it disappears from the site (kept as a draft).',
      if (!_published && !wasPublished) 'Kept as a draft — not on the site.',
      'Link: /$slug',
    ];
    final done = await _guarded(
      p == null ? 'Create post' : 'Save post',
      what,
      p == null ? 'blog.create' : 'blog.update',
      {'blog': _blog.id, 'title': title, 'slug': slug, 'published': _published, if (p != null) 'key': '${p[_blog.key]}'},
      () async {
        if (p == null) {
          await BlogApi.insert(_blog, rec);
        } else {
          await BlogApi.update(_blog, p[_blog.key] as Object, rec);
        }
      },
    );
    if (done && mounted) {
      setState(() {
        _editing = false;
        _info = p == null ? 'Post created.' : 'Post saved.';
      });
      _load();
    }
  }

  Future<void> _delete(Map<String, dynamic> p) async {
    final done = await _guarded(
      'Delete post',
      ['Deletes "${p['title']}" from ${_blog.label} for good — it can\'t be brought back from HQ.',
        if (p['published_at'] != null) 'It disappears from the site straight away.',
        'Its picture stays in storage.'],
      'blog.delete',
      {'blog': _blog.id, 'title': '${p['title']}', 'slug': '${p['slug']}', 'key': '${p[_blog.key]}'},
      () => BlogApi.delete(_blog, p[_blog.key] as Object),
    );
    if (done && mounted) {
      setState(() => _info = 'Post deleted.');
      _load();
    }
  }

  // ------------------------------------------------------------------ page

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(32), children: [
      Row(children: [
        Expanded(child: Text('Blogs', style: jost(26, weight: 600))),
        if (BlogApi.signedInAs != null)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Text('as ${BlogApi.signedInAs}', style: jost(12, color: HqColors.muted)),
          ),
        OutlinedButton(onPressed: _busy ? null : _load, child: const Text('Refresh')),
      ]),
      const SizedBox(height: 4),
      Text('Write and publish on all 5 blogs. Same database and rules as the admin pages — every change asks for Touch ID.',
          style: jost(14, color: HqColors.muted)),
      const SizedBox(height: 16),
      Choice<String>(
        options: {for (final b in BlogSite.all) b.id: b.label},
        value: _blog.id,
        onChanged: (v) => _open(BlogSite.all.firstWhere((b) => b.id == v)),
      ),
      const SizedBox(height: 14),
      if (_error != null) NoteBox(color: HqColors.bad, text: _error!),
      if (_info != null) NoteBox(color: HqColors.good, text: _info!),
      if (_editing) _editor() else ...[
        Row(children: [
          Expanded(
            child: Text(_posts == null ? 'Loading…' : '${_posts!.length} ${_posts!.length == 1 ? 'post' : 'posts'}',
                style: jost(13, weight: 500, color: HqColors.muted)),
          ),
          TextButton(onPressed: () => Process.run('open', [_blog.site]), child: const Text('Open blog page')),
          const SizedBox(width: 8),
          FilledButton(onPressed: _busy ? null : () => _edit(null), child: const Text('+ New post')),
        ]),
        const SizedBox(height: 8),
        if (_posts != null && _posts!.isEmpty) Text('No posts yet.', style: jost(13, color: HqColors.muted)),
        for (final p in _posts ?? const <Map<String, dynamic>>[]) _postRow(p),
      ],
    ]);
  }

  Widget _badge(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
        child: Text(t, style: jost(11, weight: 600, color: c)),
      );

  Widget _postRow(Map<String, dynamic> p) {
    final img = '${p['featured_image'] ?? ''}';
    final published = p['published_at'] != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: HqColors.surface,
        border: Border.all(color: HqColors.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            width: 112,
            height: 63,
            child: img.startsWith('http')
                ? Image.network(img, fit: BoxFit.cover, errorBuilder: (_, _, _) => Container(color: HqColors.line))
                : Container(color: HqColors.line),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${p['title']}', style: jost(15, weight: 600), maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              _badge(published ? 'Published' : 'Draft', published ? HqColors.good : HqColors.muted),
              if ('${p['category'] ?? ''}'.isNotEmpty) _badge('${p['category']}', HqColors.warn),
              if ('${p['daily_gem'] ?? ''}'.isNotEmpty) _badge('${p['daily_gem']}', HqColors.accent),
              Text('/${p['slug']}', style: jost(12, color: HqColors.muted)),
              if (published) Text(fmtDate(DateTime.tryParse('${p['published_at']}')), style: jost(12, color: HqColors.muted)),
            ]),
          ]),
        ),
        TextButton(onPressed: _busy ? null : () => _edit(p), child: const Text('Edit')),
        if (published)
          TextButton(onPressed: () => Process.run('open', [_blog.postUrl('${p['slug']}')]), child: const Text('View')),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: HqColors.bad),
          onPressed: _busy ? null : () => _delete(p),
          child: const Text('Delete'),
        ),
      ]),
    );
  }

  Widget _editor() {
    final img = _image.text.trim();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: HqColors.surface,
        border: Border.all(color: HqColors.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_post == null ? 'New post — ${_blog.label}' : 'Edit post — ${_blog.label}', style: jost(18, weight: 600)),
        const SizedBox(height: 12),
        TextField(
          controller: _title,
          decoration: const InputDecoration(labelText: 'Title'),
          onChanged: (v) {
            if (_post == null) _slug.text = BlogApi.slugify(v);
          },
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: TextField(controller: _slug, decoration: const InputDecoration(labelText: 'Slug (the link)'))),
          const SizedBox(width: 12),
          Expanded(child: TextField(controller: _category, decoration: const InputDecoration(labelText: 'Category'))),
          if (_blog.dailyGem) ...[
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: _dailyGem, decoration: const InputDecoration(labelText: 'Daily gem'))),
          ],
        ]),
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: TextField(
              controller: _image,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Featured image link'),
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton(onPressed: _busy ? null : _pickImage, child: const Text('Upload picture…')),
        ]),
        if (img.startsWith('http')) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(img,
                height: 140, fit: BoxFit.cover, errorBuilder: (_, _, _) => Text('Picture link doesn\'t load.', style: jost(12, color: HqColors.bad))),
          ),
        ],
        const SizedBox(height: 10),
        TextField(
          controller: _content,
          minLines: 14,
          maxLines: 30,
          style: const TextStyle(fontFamily: 'Menlo', fontSize: 13),
          decoration: const InputDecoration(
            labelText: 'Content (HTML, as on the site: <p>…</p>, <h2>…</h2>, <img src="…">)',
            alignLabelWithHint: true,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Checkbox(value: _published, onChanged: (v) => setState(() => _published = v ?? false)),
          Text('Published (shows on the site)', style: jost(14)),
          const Spacer(),
          if (_editorError != null) Text(_editorError!, style: jost(13, color: HqColors.bad)),
          const SizedBox(width: 12),
          TextButton(onPressed: () => setState(() => _editing = false), child: const Text('Cancel')),
          const SizedBox(width: 8),
          FilledButton(onPressed: _busy ? null : _save, child: Text(_post == null ? 'Create…' : 'Save…')),
        ]),
      ]),
    );
  }
}
