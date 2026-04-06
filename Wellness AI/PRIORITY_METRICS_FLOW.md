# Priority Metrics Flow Diagram

## User Journey

### Flow 1: During Onboarding

```
┌─────────────────────────────────────────────────────────────────┐
│                    ONBOARDING FLOW                              │
└─────────────────────────────────────────────────────────────────┘

Page 1: Welcome
   ↓
Page 2: Apple Watch Selection
   ↓
Page 3: Goals Selection
   ↓
Page 4: Medical Information ⭐ NEW
   ├── Add Medical Conditions
   │   ├── User types condition (e.g., "Diabetes")
   │   ├── Clicks (+) to add
   │   └── Condition appears in list with remove option
   │
   ├── Add Allergies
   │   ├── User types allergy (e.g., "Peanuts")
   │   ├── Clicks (+) to add
   │   └── Allergy appears in list with remove option
   │
   └── Click "Continue" →
       │
       ├─→ IF conditions exist:
       │   ├── Show "Analyzing your conditions..." (loading)
       │   ├── Call OpenAI API
       │   ├── Parse JSON response
       │   ├── Save Priority Metrics
       │   └── Continue to next page
       │
       └─→ IF no conditions:
           └── Skip analysis, continue to next page
   ↓
Page 5: Weight Targets
   ↓
Complete Onboarding
   ↓
Navigate to Home Tab
```

### Flow 2: From Health Tab (Post-Onboarding) ⭐

```
┌─────────────────────────────────────────────────────────────────┐
│              HEALTH TAB MEDICAL INFO FLOW                       │
└─────────────────────────────────────────────────────────────────┘

User on Health Tab
   ↓
Scroll to "Medical Information" section
   ↓
┌─────────────────────────────────────────────────────────────────┐
│  Medical Information                    [Analyze Button]        │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  Allergies                                    (+)        │   │
│  │  • Peanuts                                    (x)        │   │
│  │  • Shellfish                                  (x)        │   │
│  └──────────────────────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  Medical Conditions                           (+)        │   │
│  │  • Hypertension                               (x)        │   │
│  │  • Type 2 Diabetes                            (x)        │   │
│  │  ℹ️ Tap 'Analyze' to identify priority metrics         │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
   ↓
User clicks (+) to add condition:
   ├─→ Dialog appears
   ├─→ User types condition name
   ├─→ Clicks "Add"
   ├─→ Condition appears in list
   └─→ IF first condition: Auto-trigger AI analysis
   ↓
OR User clicks "Analyze" button:
   ├─→ Button shows loading spinner
   ├─→ "Analyze" text disappears
   ├─→ AI analyzes all conditions
   └─→ Success banner appears
   ↓
┌─────────────────────────────────────────────────────────────────┐
│  ✅ Priority metrics updated! Check Home tab...    [X]          │
└─────────────────────────────────────────────────────────────────┘
   ↓
User switches to Home tab
   ↓
Priority Metrics section shows new metrics
   ↓
User can return to Health tab anytime to:
   ├─→ Add more conditions
   ├─→ Remove conditions (triggers re-analysis)
   ├─→ Click "Analyze" to update metrics
   └─→ Clear all conditions (clears priority metrics)
```

## AI Analysis Process

```
┌─────────────────────────────────────────────────────────────────┐
│              AI MEDICAL CONDITION ANALYSIS                      │
└─────────────────────────────────────────────────────────────────┘

Input: ["Hypertension", "Type 2 Diabetes"]
   ↓
OpenAI GPT-3.5 Turbo analyzes:
   ├── Medical knowledge of each condition
   ├── Which HealthKit metrics matter most
   ├── Healthy ranges for each metric
   └── Why monitoring is important
   ↓
Returns JSON:
[
  {
    "metricName": "Resting Heart Rate",
    "icon": "heart.fill",
    "color": "red",
    "healthyRange": "60-100 BPM",
    "reason": "Critical for cardiovascular health monitoring",
    "relatedCondition": "Hypertension"
  },
  {
    "metricName": "Blood Glucose Level",
    "icon": "drop.fill",
    "color": "orange",
    "healthyRange": "70-100 mg/dL",
    "reason": "Essential for diabetes management",
    "relatedCondition": "Type 2 Diabetes"
  },
  ...
]
   ↓
Saved as PriorityMetric[] in UserGoals
   ↓
Persisted to UserDefaults
```

## Home View Display

```
┌─────────────────────────────────────────────────────────────────┐
│                        HOME TAB                                 │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│  Recent AI Insights                     │
│  ┌───────────────────────────────────┐  │
│  │  Latest recommendations...        │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
           ↓
┌─────────────────────────────────────────┐  ⭐ NEW SECTION
│  Priority Metrics                       │
│  Based on your medical conditions       │
│  ┌─────────────┐  ┌─────────────┐      │
│  │ ❤️  RHR      │  │ 🩸 Glucose   │      │
│  │ 72 BPM      │  │ 95 mg/dL    │      │
│  │ 60-100 BPM  │  │ 70-100      │      │
│  │ Hypertension│  │ Diabetes    │      │
│  └─────────────┘  └─────────────┘      │
│  ┌─────────────┐  ┌─────────────┐      │
│  │ 💤 Sleep     │  │ 🫀 HRV       │      │
│  │ 7.2 hours   │  │ 45 ms       │      │
│  │ 7-9 hours   │  │ 20-100 ms   │      │
│  │ Sleep Apnea │  │ Hypertension│      │
│  └─────────────┘  └─────────────┘      │
└─────────────────────────────────────────┘
           ↓
┌─────────────────────────────────────────┐
│  Today's Overview                       │
│  ┌──────────┐  ┌──────────┐            │
│  │ Exercise │  │  Health  │            │
│  └──────────┘  └──────────┘            │
└─────────────────────────────────────────┘
           ↓
┌─────────────────────────────────────────┐
│  Your Goals                             │
│  ...                                    │
└─────────────────────────────────────────┘
```

## Priority Metric Card Anatomy

```
┌─────────────────────────────────────────┐
│  ❤️ Resting Heart Rate           [Icon & Title]
│  
│  72 BPM                          [Current Value]
│  Healthy: 60-100 BPM             [Healthy Range]
│  
│  🏷️ Hypertension                 [Condition Badge]
│  
│  Critical for cardiovascular      [Reason/Explanation]
│  health monitoring in patients
│  with hypertension
│
│  [Border color matches metric color]
└─────────────────────────────────────────┘
```

## Health Tab UI Layout

```
┌─────────────────────────────────────────────────────────────────┐
│  Health Tab                                                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Health Recommendations                    [Generate]            │
│  ┌────────────────────────────────────────────────────────┐     │
│  │  AI-generated health recommendations...               │     │
│  └────────────────────────────────────────────────────────┘     │
│                                                                  │
│  Vital Signs                              [Week | Today]        │
│  ┌─────────────┐  ┌─────────────┐                              │
│  │ Heart Rate  │  │ Resting HR  │ ...                          │
│  └─────────────┘  └─────────────┘                              │
│                                                                  │
│  Body Measurements                                              │
│  ┌────────────────────────────────────────────────────────┐     │
│  │  Weight: 70 kg  [Edit]                                │     │
│  │  Height: 1.75 m [Edit]                                │     │
│  └────────────────────────────────────────────────────────┘     │
│                                                                  │
│  Medical Information                       [Analyze]  ⭐        │
│  ┌────────────────────────────────────────────────────────┐     │
│  │  ℹ️ If analysis succeeds:                             │     │
│  │  ✅ Priority metrics updated! Check Home tab... [X]   │     │
│  └────────────────────────────────────────────────────────┘     │
│                                                                  │
│  ┌────────────────────────────────────────────────────────┐     │
│  │  🔴 Allergies                              (+)         │     │
│  │  • Peanuts                                 (x)         │     │
│  │  • Dairy                                   (x)         │     │
│  └────────────────────────────────────────────────────────┘     │
│                                                                  │
│  ┌────────────────────────────────────────────────────────┐     │
│  │  🟠 Medical Conditions                     (+)         │     │
│  │  • Hypertension                            (x)         │     │
│  │  • Type 2 Diabetes                         (x)         │     │
│  │  ─────────────────────────────────────────────         │     │
│  │  ✅ 4 priority metrics active                          │     │
│  │     OR                                                 │     │
│  │  ℹ️ Tap 'Analyze' to identify priority metrics        │     │
│  └────────────────────────────────────────────────────────┘     │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Data Flow Architecture

```
┌─────────────────┐       ┌─────────────────┐
│  OnboardingView │   OR  │   HealthView    │
└────────┬────────┘       └────────┬────────┘
         │ User adds conditions    │
         └─────────────┬───────────┘
                       ↓
┌─────────────────────────┐
│  OpenAIAPIManager       │
│  analyzeMedicalConds()  │
└────────┬────────────────┘
         │ API call
         ↓
┌─────────────────┐
│  OpenAI GPT     │
│  Medical AI     │
└────────┬────────┘
         │ Returns JSON
         ↓
┌─────────────────────────┐
│  PriorityMetric[]       │
│  (Parsed & Validated)   │
└────────┬────────────────┘
         │ Save to UserGoals
         ↓
┌─────────────────┐
│  UserDefaults   │
│  (Persisted)    │
└────────┬────────┘
         │ Load on app start
         ↓
┌─────────────────┐
│  HomeView       │
│  Display cards  │
└─────────────────┘
         ↓
┌──────────────────────┐
│  HealthKitManager    │
│  Get current values  │
└──────────────────────┘
```

## Supported Health Metrics

The system can automatically map these metric names to HealthKit values:

✅ Heart Rate Variability (HRV)
✅ Resting Heart Rate
✅ Heart Rate
✅ Blood Pressure (Systolic/Diastolic)
✅ Oxygen Saturation (SpO2)
✅ Respiratory Rate
✅ Sleep Duration
✅ Steps Count
✅ BMI (Body Mass Index)
✅ Body Weight/Mass
✅ Wrist Temperature
✅ Stress Level (calculated)

## Example Medical Conditions → Metrics

### Hypertension
- Resting Heart Rate
- Blood Pressure
- Heart Rate Variability
- Stress Level

### Type 2 Diabetes
- Body Weight
- BMI
- Active Energy Burned
- Sleep Duration

### Asthma
- Respiratory Rate
- Oxygen Saturation
- Heart Rate

### Sleep Apnea
- Oxygen Saturation
- Sleep Duration
- Respiratory Rate
- Wrist Temperature

### Heart Disease
- Resting Heart Rate
- Heart Rate Variability
- Blood Pressure
- Active Energy

### Anxiety/Depression
- Heart Rate Variability
- Sleep Duration
- Stress Level
- Time in Daylight

---

**Visual Guide Version**: 1.0  
**Last Updated**: January 22, 2026
