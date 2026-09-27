# Asset Wizard

Version 1.2.1 refreshes the interface with a white canvas, the supplied Asset Wizard title art, rounded separated mode buttons, modern rounded inputs/actions, and removes the boxed content panel.

Version 1.2.0 redesigns the window around the Asset Wizard identity: the custom wizard illustration, two large Create New / Use Existing Assets mode buttons, and a shared framed work area.

Version 1.1.1 widens the Asset Wizard window so both Existing Assets and New Nodes have room for their full controls and labels.

Godot editor addon for common 3D asset setup tasks.

## Features

- Set up selected MeshInstance3D nodes with physics roots and generated collisions.
- Create ready-to-use scenes from imported 3D model files.
- Create new CharacterBody3D, RigidBody3D, StaticBody3D, or Area3D setups with primitive meshes and collision shapes.
- Optionally add a child detection Area3D for quick collision-testing setups.
- Undo support for scene edits and new-node creation.

## Install

Copy `addons/asset_wizard` into your project, enable **Asset Wizard** in Project Settings > Plugins, then open it from Project > Tools > Asset Wizard.

### Transparent window
Asset Wizard enables Godot's per-pixel window transparency setting so the borderless window can render only the rounded tool and overlapping mascot. On systems where the display backend only reads this setting at startup, restart the editor once after enabling the addon.
