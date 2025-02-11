import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AddRecipePage extends StatefulWidget {
  @override
  _AddRecipePageState createState() => _AddRecipePageState();
}

class _AddRecipePageState extends State<AddRecipePage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _ingredientsController = TextEditingController();
  final TextEditingController _recipeController = TextEditingController();
  int _selectedDuration = 1; // Default duration

  Future<void> _addRecipe() async {
    if (_formKey.currentState?.validate() ?? false) {
      try {
        String ingredients = _ingredientsController.text;
        String adjustedMessage = '';

        if (_selectedDuration > 1) {
          // If duration is more than 1 meal, adjust ingredients for 1 meal
          List<String> ingredientList = ingredients.split(',');
          for (int i = 0; i < ingredientList.length; i++) {
            String ingredient = ingredientList[i].trim();
            int spaceIndex = ingredient.indexOf(' ');
            if (spaceIndex != -1) {
              double quantity = double.tryParse(ingredient.substring(0, spaceIndex)) ?? 0;
              String ingredientName = ingredient.substring(spaceIndex + 1);
              ingredientList[i] = (quantity / _selectedDuration).toStringAsFixed(2) + ' $ingredientName';
            }
          }
          ingredients = ingredientList.join(', ');
          adjustedMessage = ' Ingredients have been adjusted for one meal.';
        }

        await FirebaseFirestore.instance.collection('recipes').add({
          'title': _titleController.text,
          'ingredients': ingredients,
          'recipe': _recipeController.text,
          'duration': _selectedDuration,
          'timestamp': FieldValue.serverTimestamp(),
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Recipe added successfully!' + adjustedMessage)),
        );

        // Clear the form fields
        _titleController.clear();
        _ingredientsController.clear();
        _recipeController.clear();
        setState(() {
          _selectedDuration = 1; // Reset duration to default
        });

        // Redirect to the calendar page
        Navigator.pushReplacementNamed(context, '/navigation');
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add recipe: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Add Recipe'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: <Widget>[
              TextFormField(
                controller: _titleController,
                decoration: InputDecoration(labelText: 'Title'),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a title';
                  }
                  return null;
                },
              ),
              TextFormField(
                controller: _ingredientsController,
                decoration: InputDecoration(labelText: 'Ingredients (comma-separated)'),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter ingredients';
                  }
                  return null;
                },
                maxLines: 3,
              ),
              TextFormField(
                controller: _recipeController,
                decoration: InputDecoration(labelText: 'Recipe'),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter the recipe';
                  }
                  return null;
                },
                maxLines: 5,
              ),
              DropdownButtonFormField<int>(
                value: _selectedDuration,
                items: List.generate(
                  10, // Adjust the range as needed
                  (index) => DropdownMenuItem(
                    child: Text('${index + 1} meal(s)'),
                    value: index + 1,
                  ),
                ),
                onChanged: (value) {
                  setState(() {
                    _selectedDuration = value ?? 1; // Default to 1 if value is null
                  });
                },
                decoration: InputDecoration(labelText: 'Duration'),
              ),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: _addRecipe,
                child: Text('Add Recipe'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
