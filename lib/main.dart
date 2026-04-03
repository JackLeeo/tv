import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'dart:convert';
import 'danmu/danmu_controller.dart';
import 'drpys/tvbox_parser.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter TVBox',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? _sourceUrl;
  Map<String, dynamic>? _sourceData;
  bool _isLoading = false;
  VideoPlayerController? _videoController;
  DanmuController? _danmuController;

  @override
  void initState() {
    super.initState();
    _loadSourceConfig();
  }

  Future<void> _loadSourceConfig() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _sourceUrl = prefs.getString('source_url');
    });
    if (_sourceUrl != null) {
      _loadSourceData();
    }
  }

  Future<void> _loadSourceData() async {
    if (_sourceUrl == null) return;
    setState(() {
      _isLoading = true;
    });
    try {
      final response = await http.get(Uri.parse(_sourceUrl!));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        // Use drpys parser to process the source data
        final parsedData = TvBoxParser.parseSource(data);
        setState(() {
          _sourceData = parsedData;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载源失败: $e')),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _setSourceUrl() async {
    final controller = TextEditingController(text: _sourceUrl);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('配置影视源'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: '输入TVBox接口地址',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('source_url', controller.text);
              if (mounted) {
                Navigator.pop(context, controller.text);
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (result != null) {
      setState(() {
        _sourceUrl = result;
      });
      _loadSourceData();
    }
  }

  void _playVideo(String url) {
    _videoController = VideoPlayerController.networkUrl(Uri.parse(url))
      ..initialize().then((_) {
        setState(() {});
        _videoController?.play();
        // Initialize danmaku
        _danmuController = DanmuController();
      });
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VideoPlayerPage(
          controller: _videoController!,
          danmuController: _danmuController!,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flutter TVBox'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _setSourceUrl,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_sourceUrl == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('请先配置影视源地址'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _setSourceUrl,
              child: const Text('去配置'),
            ),
          ],
        ),
      );
    }
    if (_sourceData == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('源数据加载失败，请检查地址'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadSourceData,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    // Show video list
    final videos = _sourceData!['videos'] as List? ?? [];
    return ListView.builder(
      itemCount: videos.length,
      itemBuilder: (context, index) {
        final video = videos[index];
        return ListTile(
          title: Text(video['name'] ?? ''),
          subtitle: Text(video['type'] ?? ''),
          leading: video['pic'] != null
              ? CachedNetworkImage(
                  imageUrl: video['pic'],
                  width: 50,
                  height: 75,
                  fit: BoxFit.cover,
                )
              : null,
          onTap: () {
            final playUrl = video['playUrl'];
            if (playUrl != null) {
              _playVideo(playUrl);
            }
          },
        );
      },
    );
  }
}

class VideoPlayerPage extends StatelessWidget {
  final VideoPlayerController controller;
  final DanmuController danmuController;

  const VideoPlayerPage({
    super.key,
    required this.controller,
    required this.danmuController,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('播放'),
      ),
      body: Center(
        child: Stack(
          children: [
            AspectRatio(
              aspectRatio: controller.value.aspectRatio,
              child: VideoPlayer(controller),
            ),
            // Danmaku layer
            DanmuWidget(controller: danmuController),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          controller.value.isPlaying ? controller.pause() : controller.play();
          setState(() {});
        },
        child: Icon(
          controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
        ),
      ),
    );
  }
}
