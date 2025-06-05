import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// This page allows the user to view, add, and delete custom Income and Expense categories.
/// Categories are stored in Firestore under:
///   Categories/{userId}/Transaction Categories/{Income or Expense categories}
class CategoriesManagerPage extends StatefulWidget {
  const CategoriesManagerPage({super.key});

  @override
  State<CategoriesManagerPage> createState() => _CategoriesManagerPageState();
}

class _CategoriesManagerPageState extends State<CategoriesManagerPage> {
  final String userId = FirebaseAuth.instance.currentUser!.uid;
  String selectedType = 'Income'; // Either 'Income' or 'Expense'
  late Future<DocumentSnapshot> _categoriesFuture;

  static const Color purpleColor = Color.fromARGB(255, 165, 35, 226);

  /// Loads the document from Firestore that contains the list of categories
  Future<DocumentSnapshot> _loadCategories() {
    return FirebaseFirestore.instance
        .collection('Categories')
        .doc(userId)
        .collection('Transaction Categories')
        .doc('$selectedType categories')
        .get();
  }

  /// Refreshes the categories by resetting the future
  void _refreshCategories() {
    setState(() {
      _categoriesFuture = _loadCategories();
    });
  }

  @override
  void initState() {
    super.initState();
    _categoriesFuture = _loadCategories(); // Load categories on page start
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Categories Manager"),
      ),
      body: Column(
        children: [
          // Category type toggle: Income or Expense
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: ['Income', 'Expense'].map((type) {
                return ChoiceChip(
                  label: Text(
                    type,
                    style: TextStyle(
                      color: selectedType == type ? Colors.white : purpleColor,
                    ),
                  ),
                  selected: selectedType == type,
                  selectedColor: purpleColor,
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: purpleColor),
                  showCheckmark: false,
                  onSelected: (_) {
                    setState(() {
                      selectedType = type;
                      _refreshCategories();
                    });
                  },
                );
              }).toList(),
            ),
          ),

          // Category List or Loading/Error
          Expanded(
            child: FutureBuilder<DocumentSnapshot>(
              future: _categoriesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Color.fromARGB(255, 165, 35, 226)));
                }

                if (!snapshot.hasData || !snapshot.data!.exists) {
                  return const Center(child: Text("No categories found."));
                }

                final data = snapshot.data!.data() as Map<String, dynamic>;
                // final categories = List<String>.from(data['categoryNames'] ?? []);
                final categories = List<Map<String, dynamic>>.from(data['categoryNames'] ?? []);

                return ListView.builder(
                  itemCount: categories.length + 1, // +1 for the add button
                  itemBuilder: (context, index) {
                    if (index < categories.length) {
                      final category = categories[index];
                      final categoryName = category['name'];
                      final iconPath = category['icon'] ?? 'assets/icon/deposit.png'; // deposit icon if not provided

                      return ListTile(
                        leading: Image.asset(
                          '$iconPath',
                          width: 30,
                          height: 30,
                          errorBuilder: (context, error, stackTrace) => const Icon(Icons.image_not_supported),
                        ),
                        title: Text(categoryName),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: purpleColor),
                          onPressed: () async {
                            final shouldDelete = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text("Delete Category"),
                                content: Text("Are you sure you want to delete '$categoryName'?"),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
                                  TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Delete")),
                                ],
                              ),
                            );

                            if (shouldDelete ?? false) {
                              final updatedCategories = List<Map<String, dynamic>>.from(categories)
                                ..removeWhere((cat) => cat['name'] == categoryName);

                              await FirebaseFirestore.instance
                                  .collection('Categories')
                                  .doc(userId)
                                  .collection('Transaction Categories')
                                  .doc('$selectedType categories')
                                  .update({'categoryNames': updatedCategories});

                              if (mounted) {
                                _refreshCategories();

                                // Show dialog box with success message
                                showDialog(
                                  context: context,
                                  builder: (context) {
                                    return AlertDialog(
                                      backgroundColor: const Color.fromARGB(255, 165, 35, 226),
                                      title: const Text(
                                        "Success",
                                        style: TextStyle(color: Colors.white), 
                                      ),
                                      content: Text(
                                        "Deleted '$categoryName' !",
                                        style: const TextStyle(color: Colors.white), 
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () {
                                            Navigator.of(context).pop();
                                          },
                                          child: const Text(
                                            "OK",
                                            style: TextStyle(color: Colors.white),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                );
                              }
                            }
                          },
                        ),
                      );
                    
                    } else {
                      // Render the add new category button
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10),
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final TextEditingController newCategoryController = TextEditingController();
                            String? selectedIcon = 'assets/icon/food.png'; // default icon
                            final List<String> iconPaths = [
                              'assets/icon/food.png',
                              'assets/icon/drink.png',
                              'assets/icon/transport.png',
                              'assets/icon/entertainment.png',
                              'assets/icon/sport.png',
                              'assets/icon/pen.png',
                              'assets/icon/medical.png',
                              'assets/icon/monitor.png',  
                              'assets/icon/online-shopping.png', 
                              'assets/icon/book.png',
                              'assets/icon/bill.png',
                              'assets/icon/loan.png',
                              'assets/icon/grocery.png',
                              'assets/icon/salary.png', 
                              'assets/icon/invest.png', 
                              'assets/icon/deposit.png', 
                            ];

                            final shouldAdd = await showDialog<bool>(
                              context: context,
                              builder: (context) => StatefulBuilder(
                                builder: (context, setState) => AlertDialog(
                                  title: const Text("Add New Category"),
                                  content: SingleChildScrollView(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SizedBox(
                                          width: double.maxFinite,
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              TextField(
                                                controller: newCategoryController,
                                                decoration: const InputDecoration(hintText: "Enter category name"),
                                              ),
                                              const SizedBox(height: 30),
                                              const Text("Choose an icon:"),
                                              const SizedBox(height: 8),
                                              SizedBox(
                                                height: 140, // Constraint for the GridView
                                                child: GridView.builder(
                                                  physics: const AlwaysScrollableScrollPhysics(), // Allows scrolling
                                                  itemCount: iconPaths.length,
                                                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                                    crossAxisCount: 5,
                                                    mainAxisSpacing: 4,
                                                    crossAxisSpacing: 4,
                                                  ),
                                                  itemBuilder: (context, index) {
                                                    final path = iconPaths[index];
                                                    return GestureDetector(
                                                      onTap: () => setState(() => selectedIcon = path),
                                                      child: Container(
                                                        padding: const EdgeInsets.all(4),
                                                        decoration: BoxDecoration(
                                                          border: Border.all(
                                                            color: selectedIcon == path ? Colors.deepPurple : Colors.transparent,
                                                            width: 2,
                                                          ),
                                                          borderRadius: BorderRadius.circular(8),
                                                        ),
                                                        child: Image.asset(path),
                                                      ),
                                                    );
                                                  },
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
                                    TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Add")),
                                  ],
                                ),
                              ),
                            );

                            if (shouldAdd ?? false) {
                              String newCategory = newCategoryController.text.trim();

                              if (newCategory.isNotEmpty && !categories.any((cat) => cat['name'] == newCategory)) {
                                await FirebaseFirestore.instance
                                    .collection('Categories')
                                    .doc(userId)
                                    .collection('Transaction Categories')
                                    .doc('$selectedType categories')
                                    .update({
                                      'categoryNames': FieldValue.arrayUnion([
                                        {'name': newCategory, 'icon': selectedIcon}
                                      ])
                                    });

                                if (mounted) {
                                  _refreshCategories();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text("Added '$newCategory'")),
                                  );
                                }
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text("Category already exists or is empty")),
                                );
                              }
                            }
                          },

                          icon: const Icon(Icons.add),
                          label: const Text("Add Category"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: purpleColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      );
                    }
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
