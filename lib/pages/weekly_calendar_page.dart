import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'shopping_list_page.dart';

class WeeklyCalendarPage extends StatefulWidget {
  @override
  _WeeklyCalendarPageState createState() => _WeeklyCalendarPageState();
}

class _WeeklyCalendarPageState extends State<WeeklyCalendarPage> {
  CalendarFormat _calendarFormat = CalendarFormat.week;
  DateTime _selectedDay = DateTime.now();
  Map<DateTime, List<Map<String, dynamic>>> _selectedRecipes = {};

  Future<void> _showRecipesDialog() async {
    try {
      final QuerySnapshot result =
          await FirebaseFirestore.instance.collection('recipes').get();
      final List<DocumentSnapshot> documents = result.docs;
      final List<Map<String, dynamic>> recipes =
          documents.map((doc) => doc.data() as Map<String, dynamic>).toList();

      if (recipes.isEmpty) {
        print('No recipes found in the Firestore collection.');
      }

      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('Select Recipes'),
            content: Container(
              width: double.maxFinite,
              child: GridView.builder(
                shrinkWrap: true,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 10.0,
                  mainAxisSpacing: 10.0,
                  childAspectRatio: 3.0,
                ),
                itemCount: recipes.length,
                itemBuilder: (context, index) {
                  final recipe = recipes[index];
                  final isSelected = _selectedRecipes[_selectedDay]
                          ?.any((r) => r['title'] == recipe['title']) ??
                      false;

                  return GridTile(
                    child: CheckboxListTile(
                      title: Text(recipe['title']),
                      value: isSelected,
                      onChanged: (bool? value) {
                        setState(() {
                          if (value == true) {
                            _selectedRecipes[_selectedDay] =
                                _selectedRecipes[_selectedDay] ?? [];
                            _selectedRecipes[_selectedDay]!.add({
                              'title': recipe['title'],
                              'duration': recipe['duration'],
                            });
                          } else {
                            _selectedRecipes[_selectedDay]?.removeWhere(
                                (r) => r['title'] == recipe['title']);
                          }
                        });
                      },
                    ),
                  );
                },
              ),
            ),
            actions: <Widget>[
              TextButton(
                child: Text('OK'),
                onPressed: () {
                  Navigator.of(context).pop();
                  _saveMealPlan();
                },
              ),
            ],
          );
        },
      );
    } catch (e) {
      print('Error fetching recipes: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load recipes')),
      );
    }
  }

  void _removeRecipe(Map<String, dynamic> recipe) {
    setState(() {
      _selectedRecipes[_selectedDay]?.remove(recipe);
    });
    _saveMealPlan();
  }

  // void _navigateToShoppingList() {
  //   Navigator.push(
  //     context,
  //     MaterialPageRoute(
  //       builder: (context) =>
  //           ShoppingListPage(selectedRecipes: _selectedRecipes),
  //     ),
  //   );
  // }

  Future<void> _saveMealPlan() async {
  try {
    final userMealPlans = FirebaseFirestore.instance.collection('meal_plans');
    await userMealPlans.add({
      'user_id': FirebaseAuth.instance.currentUser?.uid,
      'meal_plan': _selectedRecipes.entries.map((entry) {
        return {
          'date': entry.key.toString(),
          'recipes': entry.value.map((recipe) {
            return {
              'title': recipe['title'],
              'duration': recipe['duration'],
            };
          }).toList(),
        };
      }).toList(),
      'timestamp': FieldValue.serverTimestamp(),
    });
  } catch (e) {
    print('Error saving meal plan: $e');
  }
}


  @override
  Widget build(BuildContext context) {
    return Scaffold(

      // appBar: AppBar(
      //   title: Text('Weekly Calendar'),
      //   actions: [
      //     IconButton(
      //       icon: Icon(Icons.shopping_cart),
      //       onPressed: _navigateToShoppingList,
      //     ),
      //   ],
      // ),
      body: Column(
        children: [
          const SizedBox(height: 90),
          TableCalendar(
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2030, 12, 31),
            focusedDay: _selectedDay,
            calendarFormat: _calendarFormat,
            selectedDayPredicate: (day) {
              return isSameDay(_selectedDay, day);
            },
            onDaySelected: (selectedDay, focusedDay) {
              setState(() {
                _selectedDay = selectedDay;
              });
            },
            onFormatChanged: (format) {
              if (_calendarFormat != format) {
                setState(() {
                  _calendarFormat = format;
                });
              }
            },
            onPageChanged: (focusedDay) {
              _selectedDay = focusedDay;
            },
          ),
          Expanded(
            child: ListView(
              children: _selectedRecipes[_selectedDay]
                      ?.map((recipe) => ListTile(
                            title: Text(recipe['title']),
                            trailing: IconButton(
                              icon: Icon(Icons.delete),
                              onPressed: () => _removeRecipe(recipe),
                            ),
                          ))
                      .toList() ??
                  [],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showRecipesDialog,
        tooltip: 'Add Recipes',
        child: Icon(Icons.add),
      ),
    );
  }
}
