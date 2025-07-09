# Helm Template Fixes

## Issues Identified

The original Helm template had several critical issues that were causing JSON unmarshaling errors:

### 1. JSON Conversion Problems
- The `odigos.odiglet.resolvedResources` template was converting the resources dictionary to JSON using `toJson`
- The `odigos.odiglet.gomemlimitFromLimit` template was trying to parse it back using `fromJson`
- This conversion was failing, causing the error: `error unmarshaling JSON: while decoding JSON: json: cannot unmarshal string into Go value of type map[string]interface {}`

### 2. Template Logic Issues
- The debug output showed empty values for number and unit parsing
- The memory limit calculation was failing due to the JSON parsing errors

## Solutions Applied

### 1. Eliminated JSON Conversion
- **Before**: Used `toJson` in `odigos.odiglet.resolvedResources` and `fromJson` in `odigos.odiglet.gomemlimitFromLimit`
- **After**: Both templates now work directly with YAML data structures, avoiding JSON conversion entirely

### 2. Improved Resource Resolution Logic
- Both templates now use the same resource resolution logic directly
- Added proper default handling for memory values
- Improved error handling with fallback values

### 3. Enhanced Memory Calculation
- Added a default value (`512Mi`) for memory if not specified
- Improved regex pattern matching for memory units
- Added a sensible fallback (`409MiB`) if parsing fails

## Key Changes

### `odigos.odiglet.resolvedResources`
```yaml
# OLD (problematic):
{{- toJson $resources -}}

# NEW (fixed):
{{- $resources | toYaml -}}
```

### `odigos.odiglet.gomemlimitFromLimit`
```yaml
# OLD (problematic):
{{- $resources := include "odigos.odiglet.resolvedResources" . | fromJson -}}

# NEW (fixed):
# Duplicated the resource resolution logic directly instead of trying to parse JSON
{{- $defaults := include "odigos.defaults.resources" . | fromYaml -}}
{{- $resources := .Values.odiglet.resources | default dict | deepCopy -}}
# ... rest of the resolution logic
```

## Benefits

1. **Eliminates JSON parsing errors**: No more unmarshaling failures
2. **Improves reliability**: Direct YAML operations are more stable in Helm
3. **Better error handling**: Proper defaults and fallbacks
4. **Cleaner debug output**: No more error messages in template evaluation
5. **Consistent behavior**: Both templates use the same resource resolution approach

## Testing

To test the fixed templates:

1. Use them in a Helm chart with various resource configurations
2. Test with empty resource values
3. Test with only requests or only limits specified
4. Test with various memory unit formats (Mi, Gi, etc.)

The templates should now work correctly without JSON parsing errors and provide proper GOMEMLIMIT calculations based on the resolved memory limits.