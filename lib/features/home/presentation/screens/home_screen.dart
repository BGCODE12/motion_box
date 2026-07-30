import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../../core/constants/mock_data.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/template_model.dart';
import '../widgets/promo_carousel.dart';
import '../widgets/template_grid_item.dart';
import '../widgets/layout_template_grid_item.dart';
import '../widgets/category_toggles.dart';
import '../widgets/sub_tabs.dart';
import '../widgets/branding_bottom_sheet.dart';
import 'editor_screen.dart';

class HomeScreen extends StatefulWidget {
  final GlobalKey<ScaffoldState>? scaffoldKey;

  const HomeScreen({super.key, this.scaffoldKey});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final List<PromoBanner> _promoBanners;
  late final List<DesignTemplate> _allTemplates;
  List<DesignTemplate> _filteredTemplates = [];
  late final List<TemplateModel> _layoutTemplates;

  String _selectedMainToggle = 'Pranding';
  String _selectedSubTab = 'Animated';

  @override
  void initState() {
    super.initState();
    _promoBanners = MockData.carouselItems
        .map((item) => PromoBanner.fromMap(item))
        .toList();
    _allTemplates = MockData.designTemplates
        .map((item) => DesignTemplate.fromMap(item))
        .toList();
    _filteredTemplates = _allTemplates;
    _layoutTemplates = MockData.layoutTemplates
        .map((item) => TemplateModel.fromMap(item))
        .toList();
  }

  void _onMainToggleChanged(String toggle) {
    setState(() => _selectedMainToggle = toggle);
    if (toggle == 'Pranding') {
      showBrandingBottomSheet(context);
    }
  }

  void _onSubTabChanged(String tab) {
    setState(() => _selectedSubTab = tab);
  }

  @override
  Widget build(BuildContext context) {
    const double childAspectRatio = 117.05 / 195.09;

    return SafeArea(
      top: false,
      bottom: false,
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // App Bar
          SliverAppBar(
            expandedHeight: 70,
            floating: true,
            pinned: true,
            backgroundColor: AppTheme.background.withValues(alpha: 0.95),
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            leadingWidth: 150,
            leading: Row(
              children: [
                const SizedBox(width: 16),
                SvgPicture.asset(
                  'assets/icons/logo.svg',
                  height: 28,
                  fit: BoxFit.contain,
                ),
              ],
            ),
            actions: [
              GestureDetector(
                onTap: () {
                  if (widget.scaffoldKey != null) {
                    widget.scaffoldKey!.currentState?.openEndDrawer();
                  } else {
                    Scaffold.of(context).openEndDrawer();
                  }
                },
                child: Container(
                  width: 36,
                  height: 36,
                  margin: const EdgeInsets.only(right: 16),
                  color: Colors.transparent,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(width: 14, height: 2, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(1))),
                          const SizedBox(width: 3),
                          Container(width: 4, height: 4, decoration: const BoxDecoration(color: Color(0xFF3A7BD5), shape: BoxShape.circle)),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Container(width: 21, height: 2, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(1))),
                      const SizedBox(height: 5),
                      Container(width: 16, height: 2, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(1))),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // Carousel
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 8.0, bottom: 24.0),
              child: PromoCarousel(banners: _promoBanners),
            ),
          ),

          // Main Toggles
          SliverToBoxAdapter(
            child: CategoryToggles(
              selectedCategory: _selectedMainToggle,
              onCategoryChanged: _onMainToggleChanged,
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 24)),

          // Sub Tabs
          SliverToBoxAdapter(
            child: SubTabs(
              selectedTab: _selectedSubTab,
              onTabChanged: _onSubTabChanged,
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 24)),

          // Grid Header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Text(
                _selectedMainToggle == 'Basic' ? 'Layouts' : 'My projects',
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 16)),

          // Grid
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            sliver: (_selectedMainToggle == 'Basic' && _layoutTemplates.isEmpty) ||
                    (_selectedMainToggle != 'Basic' && _filteredTemplates.isEmpty)
                ? SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40.0),
                      child: Center(
                        child: Text(
                          _selectedMainToggle == 'Basic' ? 'No layouts available.' : 'No projects yet.',
                          style: const TextStyle(color: AppTheme.textMuted),
                        ),
                      ),
                    ),
                  )
                : SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: childAspectRatio,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 16,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        if (_selectedMainToggle == 'Basic') {
                          final template = _layoutTemplates[index];
                          return LayoutTemplateGridItem(
                            template: template,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => EditorScreen(layoutTemplate: template),
                                ),
                              );
                            },
                          );
                        } else {
                          final template = _filteredTemplates[index];
                          return TemplateGridItem(
                            template: template,
                            index: index,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => EditorScreen(designTemplate: template),
                                ),
                              );
                            },
                          );
                        }
                      },
                      childCount: _selectedMainToggle == 'Basic'
                          ? _layoutTemplates.length
                          : _filteredTemplates.length,
                    ),
                  ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }
}
