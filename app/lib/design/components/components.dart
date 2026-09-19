// The shared component set (UI/UX audit section 5, `app/lib/design/components/`).
//
// Audit design principle 5: one concept, one component. Before these existed,
// the app had four different inline treatments of "status message", a bespoke
// pill that existed on exactly one screen, an inline `_section` helper with a raw
// font size, no empty state, and no loading placeholder anywhere.
//
// Screens import this barrel rather than the individual files, so a screen's
// import list shows at a glance that it is built from the system.

export 'empty_state.dart';
export 'pill.dart';
export 'primary_action_card.dart';
export 'section_header.dart';
export 'skeleton_block.dart';
export 'status_banner.dart';
