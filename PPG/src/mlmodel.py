import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns
from sklearn.model_selection import train_test_split, cross_val_score
from sklearn.preprocessing import StandardScaler, PolynomialFeatures
from sklearn.metrics import classification_report, confusion_matrix, roc_auc_score, roc_curve, auc, accuracy_score
from sklearn.pipeline import Pipeline
from sklearn.ensemble import RandomForestClassifier, GradientBoostingClassifier, VotingClassifier, StackingClassifier
from sklearn.svm import SVC
from sklearn.linear_model import LogisticRegression
from sklearn.neural_network import MLPClassifier
import joblib
import warnings
warnings.filterwarnings('ignore')

print("======= ENHANCED STRESS PREDICTION MODEL (NO XGBOOST) =======")
print("FOCUSED VERSION: Using only HRV, Heart Rate, Blood Pressure, and Blood Oxygen")

# Load the dataset
df = pd.read_csv('stress_data.csv')
print(f"Full dataset size: {len(df)} samples")

# Filter for only Relaxed and Stressed states
filtered_df = df[df['Psychological State'].isin(['Relaxed', 'Stressed'])]
print(f"\nFiltered data shape: {filtered_df.shape}")

# Check class balance
print("\nClass distribution:")
print(filtered_df['Psychological State'].value_counts())

# Split blood pressure into systolic and diastolic
filtered_df[['Systolic', 'Diastolic']] = filtered_df['Blood Pressure (mmHg)'].str.split('/', expand=True).astype(int)

# Create base features
X = filtered_df[[
    'HRV (ms)', 
    'Heart Rate (BPM)', 
    'Systolic', 
    'Diastolic', 
    'Oxygen Saturation (%)'
]]

# Create target variable
y = (filtered_df['Psychological State'] == 'Stressed').astype(int)

# Step 1: Create advanced physiological features that might better capture stress patterns
print("\n==== CREATING ADVANCED PHYSIOLOGICAL FEATURES ====")

# Create a copy to add engineered features
extended_df = X.copy()

# Known physiological relationships
extended_df['HR_HRV_Ratio'] = extended_df['Heart Rate (BPM)'] / extended_df['HRV (ms)'] # Key stress indicator
extended_df['Pulse_Pressure'] = extended_df['Systolic'] - extended_df['Diastolic'] # Arterial stiffness
extended_df['MAP'] = extended_df['Diastolic'] + (extended_df['Pulse_Pressure'] / 3) # Mean arterial pressure
extended_df['RPP'] = extended_df['Heart Rate (BPM)'] * extended_df['Systolic'] / 100 # Rate pressure product (cardiac workload)

# Heart rate reserve approach (estimated)
extended_df['Max_HR_Estimated'] = 220 - 25  # Assuming average age of 25
extended_df['HR_Reserve_Used'] = (extended_df['Heart Rate (BPM)'] / extended_df['Max_HR_Estimated']) * 100

# HRV complexity features (simulated)
extended_df['HRV_Complexity'] = extended_df['HRV (ms)'] / extended_df['Heart Rate (BPM)'] * 10

# Create exponential and log features for non-linear relationships
for col in ['HRV (ms)', 'Heart Rate (BPM)', 'HR_HRV_Ratio']:
    extended_df[f'{col}_squared'] = extended_df[col] ** 2
    extended_df[f'{col}_cubed'] = extended_df[col] ** 3
    extended_df[f'log_{col}'] = np.log1p(np.abs(extended_df[col]))

# Interaction terms between key physiological indicators
extended_df['HR_Systolic_Interaction'] = extended_df['Heart Rate (BPM)'] * extended_df['Systolic']
extended_df['HR_Oxygen_Interaction'] = extended_df['Heart Rate (BPM)'] * extended_df['Oxygen Saturation (%)']
extended_df['HRV_Oxygen_Interaction'] = extended_df['HRV (ms)'] * extended_df['Oxygen Saturation (%)']

# Additional physiological interactions
extended_df['HRV_Diastolic'] = extended_df['HRV (ms)'] / extended_df['Diastolic']
extended_df['Oxygen_BP_Ratio'] = extended_df['Oxygen Saturation (%)'] / extended_df['MAP']
extended_df['HR_BP_Product'] = extended_df['Heart Rate (BPM)'] * extended_df['MAP'] / 100

print(f"Extended feature matrix shape: {extended_df.shape}")

# Feature correlations with target
correlations = []
for column in extended_df.columns:
    corr = np.corrcoef(extended_df[column], y)[0, 1]
    correlations.append((column, corr, abs(corr)))

# Sort by absolute correlation
correlations.sort(key=lambda x: x[2], reverse=True)
print("\nTop 10 features by correlation with stress:")
for i, (column, corr, abs_corr) in enumerate(correlations[:10]):
    print(f"{i+1}. {column}: {corr:.4f} (abs: {abs_corr:.4f})")

# Step 2: Select top features based on absolute correlation
top_features = [c[0] for c in correlations[:15]]  # Take top 15 features
print("\nSelected top features:")
print(top_features)

# Use these top features
X_selected = extended_df[top_features]

# Split the data with stratification
X_train, X_test, y_train, y_test = train_test_split(
    X_selected, y, test_size=0.25, random_state=42, stratify=y
)

print(f"\nTraining set: {X_train.shape}")
print(f"Test set: {X_test.shape}")

# Step 3: Create a powerful ensemble model
print("\n==== BUILDING ENSEMBLE MODEL (NO XGBOOST) ====")

# Define base models
base_models = [
    ('rf', RandomForestClassifier(n_estimators=300, max_depth=12, random_state=42, class_weight='balanced')),
    ('gbm', GradientBoostingClassifier(n_estimators=250, max_depth=6, learning_rate=0.08, random_state=42)),
    ('mlp', MLPClassifier(hidden_layer_sizes=(150, 75, 30), max_iter=1000, alpha=0.001, random_state=42)),
    ('svm_rbf', SVC(probability=True, kernel='rbf', gamma='auto', C=10, random_state=42)),
    ('svm_linear', SVC(probability=True, kernel='linear', C=1, random_state=42))
]

# Create a voting classifier (simpler than stacking)
voting_clf = VotingClassifier(
    estimators=base_models,
    voting='soft',  # Use probabilities for averaging
    n_jobs=-1      # Use all CPU cores
)

# Create preprocessing pipeline
model_pipeline = Pipeline([
    ('scaler', StandardScaler()),
    ('model', voting_clf)
])

# Step 4: Train the model
print("\nTraining ensemble model (this may take a while)...")
model_pipeline.fit(X_train, y_train)

# Step 5: Evaluate the model
print("\n==== EVALUATING ENSEMBLE MODEL ====")
y_pred = model_pipeline.predict(X_test)
y_prob = model_pipeline.predict_proba(X_test)[:, 1]

accuracy = accuracy_score(y_test, y_pred)
auc_score = roc_auc_score(y_test, y_prob)

print(f"Ensemble Model Test Accuracy: {accuracy:.4f}")
print(f"Ensemble Model Test AUC: {auc_score:.4f}")
print("\nClassification Report:")
print(classification_report(y_test, y_pred))
print("\nConfusion Matrix:")
print(confusion_matrix(y_test, y_pred))

# Cross-validation for stability checking
cv_scores = cross_val_score(model_pipeline, X_selected, y, cv=5, scoring='accuracy')
print(f"\nCross-validation accuracy scores: {cv_scores}")
print(f"Mean CV accuracy: {cv_scores.mean():.4f} (±{cv_scores.std():.4f})")

# Create ROC curve
plt.figure(figsize=(10, 8))
fpr, tpr, _ = roc_curve(y_test, y_prob)
roc_auc = auc(fpr, tpr)
plt.plot(fpr, tpr, label=f'ROC Curve (AUC = {roc_auc:.3f})')
plt.plot([0, 1], [0, 1], 'k--')
plt.xlim([0.0, 1.0])
plt.ylim([0.0, 1.05])
plt.xlabel('False Positive Rate')
plt.ylabel('True Positive Rate')
plt.title('Receiver Operating Characteristic')
plt.legend(loc="lower right")
plt.grid(True)
plt.savefig('ensemble_roc_curve.png')
print("Saved ROC curve")

# Individual model evaluation
print("\n==== INDIVIDUAL MODEL PERFORMANCE ====")
# Evaluate each base model separately
for name, model in base_models:
    clf = Pipeline([
        ('scaler', StandardScaler()),
        ('model', model)
    ])
    clf.fit(X_train, y_train)
    score = clf.score(X_test, y_test)
    print(f"{name} accuracy: {score:.4f}")

# Evaluate feature importance from Random Forest
rf_model = RandomForestClassifier(n_estimators=300, max_depth=12, random_state=42, class_weight='balanced')
rf_pipeline = Pipeline([
    ('scaler', StandardScaler()),
    ('model', rf_model)
])
rf_pipeline.fit(X_train, y_train)

# For tree-based models
importances = rf_model.feature_importances_
indices = np.argsort(importances)[::-1]

plt.figure(figsize=(12, 8))
plt.title('Feature Importance')
plt.bar(range(len(indices)), importances[indices], align='center')
plt.xticks(range(len(indices)), [top_features[i] for i in indices], rotation=90)
plt.tight_layout()
plt.savefig('feature_importance.png')
print("Saved feature importance plot")

# Create a prediction function using only the core metrics + derived features
def predict_stress(hrv, heart_rate, systolic, diastolic, oxygen_saturation):
    """
    Predict stress level using advanced feature engineering and ensemble model
    """
    # First create basic input data
    input_base = {
        'HRV (ms)': hrv,
        'Heart Rate (BPM)': heart_rate,
        'Systolic': systolic,
        'Diastolic': diastolic,
        'Oxygen Saturation (%)': oxygen_saturation
    }
    
    # Create all the derived features
    input_data = pd.DataFrame([input_base])
    
    # Create all the engineered features that were used in training
    input_data['HR_HRV_Ratio'] = input_data['Heart Rate (BPM)'] / input_data['HRV (ms)']
    input_data['Pulse_Pressure'] = input_data['Systolic'] - input_data['Diastolic']
    input_data['MAP'] = input_data['Diastolic'] + (input_data['Pulse_Pressure'] / 3)
    input_data['RPP'] = input_data['Heart Rate (BPM)'] * input_data['Systolic'] / 100
    input_data['Max_HR_Estimated'] = 220 - 25
    input_data['HR_Reserve_Used'] = (input_data['Heart Rate (BPM)'] / input_data['Max_HR_Estimated']) * 100
    input_data['HRV_Complexity'] = input_data['HRV (ms)'] / input_data['Heart Rate (BPM)'] * 10
    
    # Create the advanced mathematical features
    for col in ['HRV (ms)', 'Heart Rate (BPM)', 'HR_HRV_Ratio']:
        input_data[f'{col}_squared'] = input_data[col] ** 2
        input_data[f'{col}_cubed'] = input_data[col] ** 3
        input_data[f'log_{col}'] = np.log1p(np.abs(input_data[col]))
    
    # Interaction terms
    input_data['HR_Systolic_Interaction'] = input_data['Heart Rate (BPM)'] * input_data['Systolic']
    input_data['HR_Oxygen_Interaction'] = input_data['Heart Rate (BPM)'] * input_data['Oxygen Saturation (%)']
    input_data['HRV_Oxygen_Interaction'] = input_data['HRV (ms)'] * input_data['Oxygen Saturation (%)']
    input_data['HRV_Diastolic'] = input_data['HRV (ms)'] / input_data['Diastolic']
    input_data['Oxygen_BP_Ratio'] = input_data['Oxygen Saturation (%)'] / input_data['MAP']
    input_data['HR_BP_Product'] = input_data['Heart Rate (BPM)'] * input_data['MAP'] / 100
    
    # Extract only the features used in the model
    input_selected = input_data[top_features]
    
    # Predict
    probability = model_pipeline.predict_proba(input_selected)[0][1]
    prediction = "Stressed" if probability > 0.5 else "Relaxed"
    
    return prediction, probability

# Example predictions
print("\n==== EXAMPLE PREDICTIONS ====")

# Example 1: High stress profile
state1, prob1 = predict_stress(
    hrv=25,              # Low HRV - strong stress indicator
    heart_rate=110,      # High heart rate
    systolic=150,        # Elevated BP
    diastolic=95,
    oxygen_saturation=96
)
print(f"High stress profile: {state1} with {prob1:.2%} probability")

# Example 2: Low stress profile
state2, prob2 = predict_stress(
    hrv=65,              # Normal HRV
    heart_rate=72,       # Normal heart rate
    systolic=120,        # Normal BP
    diastolic=80,
    oxygen_saturation=99
)
print(f"Low stress profile: {state2} with {prob2:.2%} probability")

# Save the model
try:
    # Save the pipeline which includes both preprocessing and the model
    joblib.dump(model_pipeline, 'enhanced_stress_model.pkl')
    
    # Save metadata
    model_metadata = {
        'feature_names': top_features,
        'accuracy': accuracy,
        'auc': auc_score
    }
    
    joblib.dump(model_metadata, 'enhanced_model_metadata.pkl')
    print("\nEnhanced model and metadata saved successfully")
    
except Exception as e:
    print(f"\nError saving model: {e}")

print("\n======= ENHANCED STRESS PREDICTION MODEL COMPLETE =======")