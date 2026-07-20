# Asset Wizard

<p align="center">
Turn imported 3D models into game-ready Godot scenes in seconds.
</p>

---

## Overview

**Asset Wizard** is a Godot 4 editor plugin that automates one of the most repetitive parts of game development: preparing imported models for gameplay.

Instead of manually creating physics bodies, collision shapes, and scene hierarchies for every model, simply select one or more assets and let Asset Wizard do the work for you.

Asset Wizard works directly inside the Godot editor and supports both creating new scenes from imported models and adding physics to meshes already placed in your scenes.

---

## Features

-  Create game-ready scenes from imported models
-  Batch process multiple assets at once
-  Choose the root physics node
  - StaticBody3D
  - CharacterBody3D
  - RigidBody3D
  - Area3D
  - AnimatableBody3D
  - VehicleBody3D
-  Automatically generate collision shapes
-  Supports primitive collision shapes
  - Box
  - Sphere
  - Capsule
  - Cylinder
-  Generate Convex or Concave mesh collisions
-  Choose an output folder for generated scenes
-  Automatically names scenes from the source model
-  Converts filenames with spaces into snake_case
-  Remembers your previous settings
-  Automatically follows your Godot editor theme
-  Batch processing for large asset libraries

---

# Two Ways to Work

## FileSystem Mode

Select one or more imported models in the **FileSystem** dock.

Asset Wizard creates a new `.tscn` for every selected model.

Example:

```
chair.glb
table.glb
crate.glb
```

becomes

```
chair.tscn
table.tscn
crate.tscn
```

Each generated scene contains your chosen physics root, imported model, and collision shape.

---

## Scene Mode

Already building your level?

Select one or more **MeshInstance3D** nodes already placed in a scene.

Asset Wizard will automatically:

- Create the selected physics root
- Preserve transforms
- Move the mesh beneath the new root
- Generate the collision shape

Example:

Before

```
Node3D
├── MeshInstance3D
```

After

```
Node3D
└── CharacterBody3D
    ├── MeshInstance3D
    └── CollisionShape3D
```

No new scenes are created in this mode.

---

# Collision Options

Choose from:

- BoxShape3D
- SphereShape3D
- CapsuleShape3D
- CylinderShape3D
- ConvexPolygonShape3D
- ConcavePolygonShape3D
- SeparationRayShape3D
- HeightMapShape3D
- WorldBoundaryShape3D

Primitive shapes automatically fit the model's bounds and support adjustable padding.

For mesh collisions you can generate:

- One combined collision
- One collision per mesh

---

# Installation

1. Download the latest release.
2. Copy the `asset_wizard` folder into:

```
addons/
```

3. Open your project.
4. Enable the plugin:

```
Project
→ Project Settings
→ Plugins
```

5. Enable **Asset Wizard**.

Open the tool from:

```
Project
→ Tools
→ Asset Wizard
```

---

# Requirements

- Godot 4.7+

---

# Why Asset Wizard?

Creating gameplay-ready assets usually means repeating the same steps hundreds of times:

- Create a physics body
- Add a collision shape
- Generate collision
- Save a scene
- Repeat...

Asset Wizard automates the entire process, letting you spend more time building your game and less time setting up assets.

---

# Planned Features

- Material assignment tools
- Automatic LOD generation
- Navigation mesh generation
- Script templates
- Custom scene templates
- Batch asset processing improvements
- Additional import automation

---

# License

MIT License

---

## Support

If you find a bug or have a feature request, please open an issue on GitHub.

Contributions and feedback are always welcome!

---

Made for the **Godot Engine** community.
