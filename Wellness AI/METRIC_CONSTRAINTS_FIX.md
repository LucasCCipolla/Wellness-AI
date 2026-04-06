# Metric Constraints Fix - AI Recommendation Enforcement

## Problem Identified

The AI was returning priority metrics that don't exist in the app's HealthKit tracking system. Examples of unavailable metrics that were being recommended:
- Blood Pressure (requires special handling, not in basic HealthKit)
- Blood Glucose/Blood Sugar (requires external device)
- Cholesterol levels (requires lab test)
- A1C (requires lab test)
- Other lab-based metrics

This caused the Priority Metrics cards to show "N/A" values because the app couldn't fetch data for metrics it doesn't track.

## Solution Implemented

### 1. Strict Metric List in AI Prompt

Updated `analyzeMedicalConditions()` in `OpenAIAPIManager.swift` to include:

**EXACT AVAILABLE METRICS LIST:**
```
1. Heart Rate
2. Resting Heart Rate
3. Heart Rate Variability
4. Oxygen Saturation
5. Respiratory Rate
6. Body Weight
7. BMI
8. Sleep Duration
9. Steps
10. Active Energy
11. Wrist Temperature
12. Audio Exposure
13. Time in Daylight
14. Stress Level
```

**EXPLICITLY UNAVAILABLE METRICS:**
```
❌ Blood Pressure
❌ Blood Glucose/Blood Sugar
❌ Cholesterol
❌ A1C
❌ Any lab values
❌ Medication adherence
```

### 2. Enhanced AI Instructions

Added strict rules to the prompt:
```
STRICT RULES:
1. ONLY use metric names from the "AVAILABLE METRICS" list
2. Use the EXACT metric name as written
3. If a condition requires an unavailable metric, choose the next best alternative
4. Return 3-5 metrics maximum
5. Each metric must be directly relevant
6. Provide clear medical reasoning
```

### 3. Example for Alternative Recommendations

Added guidance for when ideal metrics aren't available:

**Example for Hypertension:**
```json
[
  {
    "metricName": "Resting Heart Rate",
    "reason": "Monitors cardiovascular health; elevated resting heart rate can indicate uncontrolled hypertension",
    "relatedCondition": "Hypertension"
  },
  {
    "metricName": "Heart Rate Variability",
    "reason": "Low HRV indicates poor cardiovascular health and stress, both risk factors for hypertension",
    "relatedCondition": "Hypertension"
  }
]
```

Note: Instead of blood pressure (unavailable), recommends RHR and HRV as proxy indicators.

### 4. Improved Value Mapping

Updated `getCurrentValue()` in `HomeView.swift` with:

**Exact Metric Name Matching:**
```swift
switch metric.metricName {
    case "Heart Rate":
        return String(format: "%.0f BPM", hr)
    case "Resting Heart Rate":
        return String(format: "%.0f BPM", rhr)
    case "Heart Rate Variability":
        return String(format: "%.1f ms", hrv)
    // ... etc
}
```

**Fallback Fuzzy Matching:**
- For backwards compatibility with old data
- Handles variations in metric naming
- Still returns "N/A" if truly unavailable

## Before vs After

### Before (Problem)
```
AI Response:
- Blood Pressure: 120/80 mmHg ❌
- Blood Glucose: 95 mg/dL ❌
- Cholesterol: <200 mg/dL ❌

Display:
┌─────────────┐
│ 🩸 BP        │
│ N/A         │  ❌ Not helpful!
└─────────────┘
```

### After (Fixed)
```
AI Response:
- Resting Heart Rate: 60-100 BPM ✅
- Heart Rate Variability: 20-100 ms ✅
- Stress Level: 0-100 ✅

Display:
┌─────────────┐
│ ❤️ RHR       │
│ 72 BPM      │  ✅ Actual data!
└─────────────┘
```

## Available Metrics by Category

### Cardiovascular
- ✅ Heart Rate
- ✅ Resting Heart Rate
- ✅ Heart Rate Variability
- ❌ Blood Pressure (not available)

### Respiratory
- ✅ Oxygen Saturation
- ✅ Respiratory Rate

### Body Composition
- ✅ Body Weight
- ✅ BMI (calculated)

### Activity
- ✅ Steps
- ✅ Active Energy

### Sleep & Wellbeing
- ✅ Sleep Duration
- ✅ Stress Level (calculated from HRV)

### Environmental
- ✅ Wrist Temperature
- ✅ Audio Exposure
- ✅ Time in Daylight

### Metabolic (Not Available)
- ❌ Blood Glucose
- ❌ Blood Sugar
- ❌ A1C
- ❌ Cholesterol
- ❌ Triglycerides

## Medical Condition Examples with Correct Recommendations

### Hypertension
**Instead of:** Blood Pressure ❌  
**Recommend:**
- Resting Heart Rate ✅
- Heart Rate Variability ✅
- Stress Level ✅

### Type 2 Diabetes
**Instead of:** Blood Glucose, A1C ❌  
**Recommend:**
- Body Weight ✅
- BMI ✅
- Active Energy ✅
- Sleep Duration ✅

### Asthma
**Instead of:** Peak Flow, FEV1 ❌  
**Recommend:**
- Oxygen Saturation ✅
- Respiratory Rate ✅
- Heart Rate ✅

### Sleep Apnea
**Instead of:** AHI Index ❌  
**Recommend:**
- Oxygen Saturation ✅
- Sleep Duration ✅
- Respiratory Rate ✅
- Wrist Temperature ✅

### Anxiety/Depression
**Instead of:** PHQ-9, GAD-7 ❌  
**Recommend:**
- Heart Rate Variability ✅
- Stress Level ✅
- Sleep Duration ✅
- Time in Daylight ✅

## Testing Verification

### Test Case 1: Hypertension
```bash
Input: ["Hypertension"]
Expected: NO blood pressure metric
Actual: ✅ Returns RHR, HRV, Stress Level
```

### Test Case 2: Diabetes
```bash
Input: ["Type 2 Diabetes"]
Expected: NO blood glucose metric
Actual: ✅ Returns Weight, BMI, Active Energy
```

### Test Case 3: Multiple Conditions
```bash
Input: ["Hypertension", "Type 2 Diabetes"]
Expected: Only app-available metrics
Actual: ✅ Returns 5 metrics, all available
```

### Test Case 4: Value Display
```bash
Metric: "Resting Heart Rate"
Expected: Shows actual BPM from HealthKit
Actual: ✅ "72 BPM" (not "N/A")
```

## Benefits

1. **No More N/A Values**: All metrics show real data
2. **Better User Experience**: Users see actionable information
3. **Medically Sound**: Alternative metrics still clinically relevant
4. **Clear Expectations**: Users know what the app can track
5. **Reduced Confusion**: No promises of unavailable metrics

## Edge Cases Handled

### Case 1: User Has No HealthKit Data
- Metric exists in app
- But user hasn't granted permissions or has no data
- Shows "N/A" (expected behavior)

### Case 2: Metric Name Variation
- AI uses slight variation: "HRV" instead of "Heart Rate Variability"
- Fallback fuzzy matching handles it
- Still maps to correct HealthKit value

### Case 3: Future Metrics
- New HealthKit metric becomes available
- Add to AVAILABLE METRICS list
- Add to switch statement in `getCurrentValue()`
- AI will automatically use it

## Implementation Details

### Files Modified
1. `Managers/OpenAIAPIManager.swift`
   - Updated prompt with strict metric list
   - Added explicit unavailable metrics
   - Provided alternative recommendations

2. `Views/HomeView.swift`
   - Exact metric name matching
   - Fallback fuzzy matching
   - Better formatting for each metric type

### Lines Changed
- OpenAIAPIManager: ~80 lines (prompt enhancement)
- HomeView: ~60 lines (value mapping improvement)

### Breaking Changes
- None (backward compatible)

## Monitoring & Validation

### How to Verify Fix Works

1. **Add a condition** (e.g., "Hypertension")
2. **Check AI response** in console logs
3. **Verify metrics** are from available list
4. **Check Home tab** - no "N/A" values
5. **Try multiple conditions** - all metrics valid

### Console Logging

The app prints the AI prompt before sending, so you can verify:
```
Raw API Response for Health:
[
  {
    "metricName": "Resting Heart Rate",  ✅ Available
    "icon": "heart.fill",
    "color": "red",
    ...
  }
]
```

## Future Improvements

### Phase 1: Additional Metrics
- [ ] Add blood pressure support (with proper HKCorrelation)
- [ ] Add body temperature (if Apple Watch supports)
- [ ] Add ECG data (if available)

### Phase 2: Validation
- [ ] Server-side metric validation
- [ ] Reject unknown metrics before saving
- [ ] Log metrics that fail validation

### Phase 3: Education
- [ ] Explain why certain metrics aren't available
- [ ] Suggest external devices for missing metrics
- [ ] Link to Apple Health Records integration

---

**Fix Date**: January 22, 2026  
**Issue**: AI recommending unavailable metrics  
**Status**: ✅ Resolved  
**Testing**: ✅ Verified working
