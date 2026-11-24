
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BaghdadPharmacyApp());
}

class PharmacyItem {
  final String id;
  String name;
  String category;
  double price;
  String note;

  PharmacyItem({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    this.note = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        'price': price,
        'note': note,
      };

  factory PharmacyItem.fromJson(Map<String, dynamic> json) {
    return PharmacyItem(
      id: json['id']?.toString() ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      name: json['name']?.toString() ?? '',
      category: json['category']?.toString() ?? 'عام',
      price: double.tryParse(json['price']?.toString() ?? '0') ?? 0,
      note: json['note']?.toString() ?? '',
    );
  }
}

class BaghdadPharmacyApp extends StatelessWidget {
  const BaghdadPharmacyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'صيدلية بغداد',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar', 'YE'),
      supportedLocales: const [
        Locale('ar', 'YE'),
        Locale('ar'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0D6E6E),
        ),
        useMaterial3: true,
        textTheme: GoogleFonts.cairoTextTheme(),
      ),
      home: const PharmacyHomeScreen(),
    );
  }
}

class PharmacyHomeScreen extends StatefulWidget {
  const PharmacyHomeScreen({super.key});

  @override
  State<PharmacyHomeScreen> createState() => _PharmacyHomeScreenState();
}

class _PharmacyHomeScreenState extends State<PharmacyHomeScreen> {
  static const String _storageKey = 'baghdad_pharmacy_items_v1';

  // رمز الإدارة الافتراضي
  final String _adminPin = '1234';

  // أرقام واتساب الطلبات
  final List<String> _whatsappNumbers = [
    '967771350505',
    '967733313664',
  ];

  String _selectedCategory = 'الكل';
  String _searchQuery = '';
  bool _isLoadingItems = true;

  final List<PharmacyItem> _defaultItems = [
    PharmacyItem(
      id: '1',
      name: 'باراسيتامول 500 ملغ',
      category: 'مسكنات',
      price: 800,
      note: 'شريط أو عبوة حسب التوفر',
    ),
    PharmacyItem(
      id: '2',
      name: 'فيتامين سي فوار',
      category: 'فيتامينات ومكملات',
      price: 2500,
      note: 'مكمل غذائي',
    ),
    PharmacyItem(
      id: '3',
      name: 'محلول معقم للجروح',
      category: 'عناية ومستلزمات',
      price: 1500,
      note: 'استخدام خارجي',
    ),
  ];

  List<PharmacyItem> _items = [];

  // الكميات المختارة لكل صنف
  final Map<String, int> _cartQuantities = {};

  @override
  void initState() {
    super.initState();
    _loadSavedItems();
  }

  Future<void> _loadSavedItems() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawJson = prefs.getString(_storageKey);

      if (rawJson != null && rawJson.trim().isNotEmpty) {
        final decoded = jsonDecode(rawJson);

        if (decoded is List) {
          // تم تصحيح الخطأ هنا
          final loaded = decoded
              .where((e) => e is Map)
              .map(
                (e) => PharmacyItem.fromJson(
                  Map<String, dynamic>.from(e as Map),
                ),
              )
              .toList();

          if (mounted) {
            setState(() {
              _items = loaded;
              _isLoadingItems = false;
            });
          }
          return;
        }
      }

      // أول تشغيل: تحميل الأصناف الافتراضية
      final initialCopy = _defaultItems
          .map((e) => PharmacyItem.fromJson(e.toJson()))
          .toList();

      if (mounted) {
        setState(() {
          _items = initialCopy;
          _isLoadingItems = false;
        });
      }

      await _saveItemsToStorage();
    } catch (e) {
      if (mounted) {
        setState(() {
          _items = _defaultItems
              .map((e) => PharmacyItem.fromJson(e.toJson()))
              .toList();
          _isLoadingItems = false;
        });
      }
    }
  }

  Future<void> _saveItemsToStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_items.map((e) => e.toJson()).toList());
    await prefs.setString(_storageKey, encoded);
  }

  List<String> get _categories {
    final categories = <String>{'الكل'};

    for (final item in _items) {
      if (item.category.trim().isNotEmpty) {
        categories.add(item.category.trim());
      }
    }

    return categories.toList();
  }

  List<PharmacyItem> get _filteredItems {
    return _items.where((item) {
      final matchesCategory = _selectedCategory == 'الكل' ||
          item.category == _selectedCategory;

      final query = _searchQuery.trim().toLowerCase();

      final matchesSearch = query.isEmpty ||
          item.name.toLowerCase().contains(query) ||
          item.category.toLowerCase().contains(query);

      return matchesCategory && matchesSearch;
    }).toList();
  }

  double get _totalAmount {
    double total = 0;

    for (final item in _items) {
      final qty = _cartQuantities[item.id] ?? 0;
      total += item.price * qty;
    }

    return total;
  }

  int get _totalItemsCount {
    int count = 0;

    for (final qty in _cartQuantities.values) {
      count += qty;
    }

    return count;
  }

  Future<void> _sendOrderToWhatsapp(String phone) async {
    final selectedLines = <String>[];

    for (final item in _items) {
      final qty = _cartQuantities[item.id] ?? 0;

      if (qty > 0) {
        final lineTotal = item.price * qty;

        selectedLines.add(
          '• ${item.name} × $qty (${lineTotal.toStringAsFixed(0)})',
        );
      }
    }

    if (selectedLines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('اختر صنفاً واحداً على الأقل قبل إرسال الطلب'),
        ),
      );
      return;
    }

    final message = StringBuffer()
      ..writeln('السلام عليكم، أود طلب الأصناف التالية من صيدلية بغداد:')
      ..writeln()
      ..writeln(selectedLines.join('\n'))
      ..writeln()
      ..writeln('الإجمالي التقديري: ${_totalAmount.toStringAsFixed(0)}');

    final encoded = Uri.encodeComponent(message.toString());
    final uri = Uri.parse('https://wa.me/$phone?text=$encoded');

    try {
      final opened = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر فتح واتساب على الجهاز')),
        );
      }
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر فتح واتساب على الجهاز')),
      );
    }
  }

  void _openPinDialog() {
    final pinController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('دخول إدارة الأصناف'),
        content: TextField(
          controller: pinController,
          keyboardType: TextInputType.number,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'أدخل رمز الإدارة',
            hintText: 'مثال: 1234',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              if (pinController.text.trim() == _adminPin) {
                Navigator.pop(ctx);
                _openManageItemsSheet();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('رمز الإدارة غير صحيح'),
                  ),
                );
              }
            },
            child: const Text('دخول'),
          ),
        ],
      ),
    );
  }

  void _openAddItemDialog({PharmacyItem? existingItem}) {
    final nameController = TextEditingController(
      text: existingItem?.name ?? '',
    );

    final categoryController = TextEditingController(
      text: existingItem?.category ?? 'عام',
    );

    final priceController = TextEditingController(
      text: existingItem != null
          ? existingItem.price.toStringAsFixed(0)
          : '',
    );

    final noteController = TextEditingController(
      text: existingItem?.note ?? '',
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          existingItem == null ? 'إضافة صنف جديد' : 'تعديل صنف',
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'اسم الصنف *',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: categoryController,
                decoration: const InputDecoration(
                  labelText: 'القسم',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: priceController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'السعر *',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: noteController,
                decoration: const InputDecoration(
                  labelText: 'ملاحظة / وصف مختصر',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();

              final category = categoryController.text.trim().isEmpty
                  ? 'عام'
                  : categoryController.text.trim();

              final price =
                  double.tryParse(priceController.text.trim()) ?? 0;

              final note = noteController.text.trim();

              if (name.isEmpty || price <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('يرجى إدخال اسم الصنف وسعر صحيح'),
                  ),
                );
                return;
              }

              setState(() {
                if (existingItem == null) {
                  _items.add(
                    PharmacyItem(
                      id: DateTime.now()
                          .millisecondsSinceEpoch
                          .toString(),
                      name: name,
                      category: category,
                      price: price,
                      note: note,
                    ),
                  );
                } else {
                  existingItem.name = name;
                  existingItem.category = category;
                  existingItem.price = price;
                  existingItem.note = note;
                }
              });

              await _saveItemsToStorage();

              if (!ctx.mounted) return;
              Navigator.pop(ctx);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  void _openManageItemsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.75,
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Flexible(
                          child: Text(
                            'إدارة أصناف صيدلية بغداد',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _openAddItemDialog();
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('إضافة صنف'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView.separated(
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const Divider(),
                        itemBuilder: (context, index) {
                          final item = _items[index];

                          return ListTile(
                            title: Text(item.name),
                            subtitle: Text(
                              '${item.category} • السعر: ${item.price.toStringAsFixed(0)}',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit),
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    _openAddItemDialog(
                                      existingItem: item,
                                    );
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () async {
                                    setState(() {
                                      _cartQuantities.remove(item.id);
                                      _items.removeAt(index);
                                    });

                                    await _saveItemsToStorage();
                                    setModalState(() {});
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'عدد الأصناف المحفوظة: ${_items.length}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _filteredItems;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                  'assets/images/logo.png',
                  width: 34,
                  height: 34,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.local_pharmacy),
                ),
              ),
              const SizedBox(width: 10),
              const Text('صيدلية بغداد'),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'إدارة الأصناف',
              icon: const Icon(Icons.inventory_2_outlined),
              onPressed: _openPinDialog,
            ),
          ],
        ),
        body: _isLoadingItems
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                    child: TextField(
                      onChanged: (val) {
                        setState(() => _searchQuery = val);
                      },
                      decoration: InputDecoration(
                        hintText: 'ابحث عن صنف أو قسم...',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        isDense: true,
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 44,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: _categories.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final cat = _categories[index];
                        final selected = cat == _selectedCategory;

                        return ChoiceChip(
                          label: Text(cat),
                          selected: selected,
                          onSelected: (_) {
                            setState(() => _selectedCategory = cat);
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: items.isEmpty
                        ? const Center(
                            child: Text('لا توجد أصناف مطابقة حالياً'),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: items.length,
                            itemBuilder: (context, index) {
                              final item = items[index];
                              final qty =
                                  _cartQuantities[item.id] ?? 0;

                              return Card(
                                margin: const EdgeInsets.only(bottom: 10),
                                child: ListTile(
                                  title: Text(
                                    item.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${item.category} • ${item.price.toStringAsFixed(0)} ريال',
                                      ),
                                      if (item.note.isNotEmpty)
                                        Text(
                                          item.note,
                                          style: const TextStyle(
                                            fontSize: 12,
                                          ),
                                        ),
                                    ],
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (qty > 0)
                                        IconButton(
                                          icon: const Icon(
                                            Icons.remove_circle_outline,
                                          ),
                                          onPressed: () {
                                            setState(() {
                                              if (qty <= 1) {
                                                _cartQuantities
                                                    .remove(item.id);
                                              } else {
                                                _cartQuantities[item.id] =
                                                    qty - 1;
                                              }
                                            });
                                          },
                                        ),
                                      if (qty > 0)
                                        Text(
                                          '$qty',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.add_circle_outline,
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            _cartQuantities[item.id] =
                                                qty + 1;
                                          });
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
        bottomNavigationBar: SafeArea(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: Colors.black12),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('الأصناف المختارة: $_totalItemsCount'),
                    Text(
                      'الإجمالي: ${_totalAmount.toStringAsFixed(0)} ريال',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          _sendOrderToWhatsapp(_whatsappNumbers[0]);
                        },
                        icon: const Icon(Icons.chat),
                        label: const Text('طلب عبر واتساب (771)'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          _sendOrderToWhatsapp(_whatsappNumbers[1]);
                        },
                        icon: const Icon(Icons.chat),
                        label: const Text('واتساب (733)'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
