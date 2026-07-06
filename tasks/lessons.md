# Lessons Learned

## Leg 3 UI Implementation

- **SwiftUI Non-Optional Bindings**:
  - *Rule*: Never use conditional optional binding (`if let ...`) on non-optional fields (like `confidence` on `TokenUsage`), as the Swift compiler will fail with an error. Always check the property type in the core models before writing SwiftUI conditional rendering logic.
- **Dynamic Render Performance & UI Redraw**:
  - *Rule*: When designing countdown timers in SwiftUI that rely on system dates (`Date()`), use a local view state variable mapped to a `Timer.publish` stream. To ensure reactivity inside views/methods, reference the state variable inside the formatter method (`let _ = countdownTick`) to trigger redraws correctly.
