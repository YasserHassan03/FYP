import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class ShoppingListPage extends StatelessWidget {
  final Map<DateTime, List<Map<String, dynamic>>> selectedRecipes;

  ShoppingListPage({required this.selectedRecipes});

  Future<Map<String, int>> _aggregateIngredients() async {
    final Map<String, int> ingredientCounts = {};

    for (var date in selectedRecipes.keys) {
      for (var recipe in selectedRecipes[date]!) {
        final QuerySnapshot result = await FirebaseFirestore.instance
            .collection('recipes')
            .where('title', isEqualTo: recipe['title'])
            .get();

        if (result.docs.isNotEmpty) {
          final recipeData = result.docs.first.data() as Map<String, dynamic>;
          final ingredients = recipeData['ingredients'].split(',');

          for (var ingredient in ingredients) {
            ingredient = ingredient.trim();
            int duration = recipe['duration'];

            if (ingredientCounts.containsKey(ingredient)) {
              ingredientCounts[ingredient] =
                  ingredientCounts[ingredient]! + duration;
            } else {
              ingredientCounts[ingredient] = duration;
            }
          }
        }
      }
    }

    return ingredientCounts;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Shopping List'),
      ),
      body: FutureBuilder<Map<String, int>>(
        future: _aggregateIngredients(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else {
            final ingredients = snapshot.data ?? {};

            return ListView(
              padding: const EdgeInsets.all(16.0),
              children: ingredients.entries.map((entry) {
                return ListTile(
                  title: Text('${entry.key}'),
                  trailing: Text('${entry.value}'),
                );
              }).toList(),
            );
          }
        },
      ),
    );
  }
}
