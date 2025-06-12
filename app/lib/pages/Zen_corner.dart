import 'package:flutter/material.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'video_player_screen.dart'; // Import the VideoPlayerScreen

class ZenCorner extends StatefulWidget {
  const ZenCorner({Key? key}) : super(key: key);

  @override
  State<ZenCorner> createState() => _ZenCornerState();
}

class _ZenCornerState extends State<ZenCorner>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 5, // Make sure this is 5 to match the number of tabs
      vsync: this,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Tab bar for categories
        Padding(
          padding: const EdgeInsets.only(
            top: 40,
          ), // Adding top padding to move the tab bar down
          child: TabBar(
            controller: _tabController,
            labelColor: Colors.indigoAccent,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.indigoAccent,
            isScrollable: true, // Make tabs scrollable for small screens
            tabs: const [
              Tab(text: "Sports Psychology", icon: Icon(Icons.psychology)),
              Tab(text: "Meditation", icon: Icon(Icons.self_improvement)),
              Tab(text: "Breathing", icon: Icon(Icons.air)),
              Tab(text: "Physical", icon: Icon(Icons.fitness_center)),
              Tab(text: "Sleep", icon: Icon(Icons.bedtime)),
            ],
          ),
        ),

        // Tab view for videos
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
                            // Sports Psychology/Education videos
              VideoCategory(
                videos: [
                  VideoItem(
                    title: "Inside the mind of champion athletes",
                    videoId: "yG7v4y_xwzQ",
                    description: "Understanding psychology in sports",
                  ),
                  VideoItem(
                    title: "What gives Elite Athletes the Edge?",
                    videoId: "Y7J-WvrI4DM",
                    description:
                        "Janne Mortensen talks about developing the mind of a winner",
                  ),
                  VideoItem(
                    title: "Motivation to work",
                    videoId: "jrIS_RQJmCU",
                    description:
                        "Andrew Huberman on motivation and productivity",
                  ),
                  VideoItem(
                    title: "How to stay calm under pressure",
                    videoId: "CqgmozFr_GM",
                    description: "Lesson by Noa Kageyama and Pen-Pen Chen",
                  ),
                ],
              ),
              // Meditation videos
              VideoCategory(
                videos: [
                  VideoItem(
                    title: "5-Minute Meditation for Stress Relief",
                    videoId: "inpok4MKVLM",
                    description:
                        "Quick meditation practice to help you relieve stress",
                  ),
                  VideoItem(
                    title: "Guided Meditation for Anxiety & Stress",
                    videoId: "O-6f5wQXSu8",
                    description:
                        "15-minute guided meditation to reduce anxiety",
                  ),
                  VideoItem(
                    title: "Mindfulness Meditation",
                    videoId: "ZToicYcHIOU",
                    description: "Learn the basics of mindfulness meditation",
                  ),
                ],
              ),

              // Breathing exercises
              VideoCategory(
                videos: [
                  VideoItem(
                    title: "Box Breathing Technique",
                    videoId: "tEmt1Znux58",
                    description: "Learn the 4-4-4-4 box breathing method",
                  ),
                  VideoItem(
                    title: "4-7-8 Breathing Exercise",
                    videoId: "PmBYdfv5RSk",
                    description: "Dr. Weil's famous relaxation technique",
                  ),
                  VideoItem(
                    title: "Diaphragmatic Breathing",
                    videoId: "UB3tSaiEbNY",
                    description: "Deep belly breathing for stress relief",
                  ),
                ],
              ),

              // Physical exercises
              VideoCategory(
                videos: [
                  VideoItem(
                    title: "10-Minute Stress Relief Yoga",
                    videoId: "sTANio_2E0Q",
                    description: "Quick yoga sequence to release tension",
                  ),
                  VideoItem(
                    title: "Progressive Muscle Relaxation",
                    videoId: "86HUcX8ZtAk",
                    description: "Technique to relax your entire body",
                  ),
                  VideoItem(
                    title: "5-Minute Desk Stretches",
                    videoId: "JUP_YdYyfQw",
                    description: "Quick stretches you can do at your desk",
                  ),
                ],
              ),

              // Sleep aids
              VideoCategory(
                videos: [
                  VideoItem(
                    title: "Sleep Meditation for Anxiety",
                    videoId: "acLUWBuAvms",
                    description: "Guided meditation to help you fall asleep",
                  ),
                  VideoItem(
                    title: "Body Scan for Sleep",
                    videoId: "T5ut2NYdAEQ",
                    description: "Progressive body relaxation for better sleep",
                  ),
                  VideoItem(
                    title: "Guided Sleep Meditation",
                    videoId: "U6Ay9v7gK9w", // Changed to a working video ID
                    description: "Guided meditation to help you sleep",
                  ),
                ],
              ),


            ],
          ),
        ),
      ],
    );
  }
}

// Widget to display a category of videos
class VideoCategory extends StatelessWidget {
  final List<VideoItem> videos;

  const VideoCategory({Key? key, required this.videos}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: videos.length,
      itemBuilder: (context, index) {
        return VideoCard(video: videos[index]);
      },
    );
  }
}

// Data class for video information
class VideoItem {
  final String title;
  final String videoId;
  final String description;

  const VideoItem({
    required this.title,
    required this.videoId,
    required this.description,
  });
}

// Widget to display a single video
class VideoCard extends StatelessWidget {
  final VideoItem video;

  const VideoCard({Key? key, required this.video}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 4,
      shadowColor: Colors.grey[400],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Video thumbnail with play button
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder:
                      (context) => VideoPlayerScreen(videoId: video.videoId),
                ),
              );
            },
            child: Stack(
              alignment: Alignment.center,
              children: [
                // YouTube thumbnail with error handling
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: FadeInImage.assetNetwork(
                      placeholder:
                          'assets/placeholder.png', // Create a placeholder image in your assets
                      image:
                          'https://img.youtube.com/vi/${video.videoId}/0.jpg',
                      fit: BoxFit.cover,
                      imageErrorBuilder: (context, error, stackTrace) {
                        // Return a placeholder on error
                        return Container(
                          color: Colors.grey[300],
                          child: Center(
                            child: Icon(
                              Icons.video_library,
                              size: 50,
                              color: Colors.grey[600],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                // Play button overlay
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
              ],
            ),
          ),
          // Video info
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  video.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  video.description,
                  style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
