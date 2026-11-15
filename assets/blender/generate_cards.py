import math
import os
import bpy
from mathutils import Euler

OUT_DIR = r"c:\Users\nicol\OneDrive - studmail.w-hs.de\Antigravity_Projekte\06_Zaubera\assets\cards"
BLEND_PATH = r"c:\Users\nicol\OneDrive - studmail.w-hs.de\Antigravity_Projekte\06_Zaubera\assets\blender\wizard_cards.blend"
os.makedirs(OUT_DIR, exist_ok=True)
os.makedirs(os.path.dirname(BLEND_PATH), exist_ok=True)


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def smooth(obj):
    if obj and obj.type == "MESH":
        for p in obj.data.polygons:
            p.use_smooth = True


def make_mat(name, base_color, metallic=0.1, roughness=0.3, emission=(0, 0, 0), emission_strength=0.0):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*base_color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if "Emission Color" in bsdf.inputs:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    return mat


def setup_render(res_x, res_y, transparent=True):
    scene = bpy.context.scene
    for eng in ["BLENDER_EEVEE_NEXT", "BLENDER_EEVEE", "CYCLES"]:
        try:
            scene.render.engine = eng
            break
        except Exception:
            pass
    scene.render.resolution_x = res_x
    scene.render.resolution_y = res_y
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = transparent
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA" if transparent else "RGB"
    scene.view_settings.view_transform = "Standard"

    # Rich world ambient for metallic reflections
    world = bpy.data.worlds.new("StudioWorld")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (0.18, 0.22, 0.34, 1.0)
    bg.inputs["Strength"].default_value = 1.2

    def add_light(name, ltype, loc, rot_deg, energy, color=(1, 1, 1), size=3.5):
        ldata = bpy.data.lights.new(name=name, type=ltype)
        ldata.energy = energy
        ldata.color = color
        if hasattr(ldata, "size"):
            ldata.size = size
        lobj = bpy.data.objects.new(name, ldata)
        bpy.context.collection.objects.link(lobj)
        lobj.location = loc
        lobj.rotation_euler = Euler([math.radians(a) for a in rot_deg], 'XYZ')
        return lobj

    add_light("KeyLight", "AREA", (2.2, -2.5, 4.8), (28, 18, 22), 320.0, (1.0, 0.96, 0.88), 3.2)
    add_light("RimLight", "AREA", (-2.6, 2.2, 3.6), (-32, -28, 0), 240.0, (0.78, 0.90, 1.0), 3.0)
    add_light("FillLight", "AREA", (0.0, -3.2, 2.6), (48, 0, 0), 110.0, (0.95, 0.95, 1.0), 4.5)

    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 2.35
    cam_obj = bpy.data.objects.new("Cam", cam_data)
    bpy.context.collection.objects.link(cam_obj)
    cam_obj.location = (0, 0, 5.0)
    cam_obj.rotation_euler = (0, 0, 0)
    scene.camera = cam_obj
    return scene, cam_data


def render_to(filename):
    bpy.context.scene.render.filepath = os.path.join(OUT_DIR, filename)
    bpy.ops.render.render(write_still=True)


def clear_meshes():
    for obj in list(bpy.data.objects):
        if obj.type == "MESH":
            bpy.data.objects.remove(obj, do_unlink=True)


def add_beveled_cube(name, size_xyz, loc=(0, 0, 0), rot=(0, 0, 0), bevel_w=0.05, mat=None, do_smooth=True):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = size_xyz
    obj.rotation_euler = Euler([math.radians(a) for a in rot], 'XYZ')
    bpy.ops.object.transform_apply(scale=True)
    bev = obj.modifiers.new("Bevel", "BEVEL")
    bev.width = bevel_w
    bev.segments = 5
    if mat:
        obj.data.materials.append(mat)
    if do_smooth:
        smooth(obj)
    return obj


def build_suit_red():
    clear_meshes()
    gold = make_mat("Gold", (0.98, 0.78, 0.24), metallic=0.92, roughness=0.16)
    ruby = make_mat("Ruby", (0.95, 0.12, 0.14), metallic=0.18, roughness=0.10, emission=(0.85, 0.08, 0.05), emission_strength=0.45)
    core = make_mat("FlameCore", (1.0, 0.80, 0.22), metallic=0.1, roughness=0.15, emission=(1.0, 0.65, 0.12), emission_strength=1.5)

    # Smooth gold halo ring
    bpy.ops.mesh.primitive_torus_add(major_radius=0.88, minor_radius=0.055, major_segments=64, minor_segments=24, location=(0, 0, -0.08))
    ring = bpy.context.active_object
    ring.data.materials.append(gold)
    smooth(ring)

    # Symmetrical faceted Ruby Flame Diamond (built with ZYX Euler so diamond stays upright!)
    ruby_gem = add_beveled_cube("RubyDiamond", (0.94, 0.94, 0.34), (0, 0, 0.12), (0, 0, 45), 0.04, ruby, do_smooth=False)
    ruby_gem.scale = (0.76, 1.08, 1.0)
    core_gem = add_beveled_cube("CoreDiamond", (0.44, 0.44, 0.24), (0, 0, 0.28), (0, 0, 45), 0.02, core, do_smooth=False)
    core_gem.scale = (0.76, 1.08, 1.0)
    render_to("suit_red.png")


def build_suit_blue():
    clear_meshes()
    silver = make_mat("FrostSilver", (0.86, 0.95, 1.0), metallic=0.90, roughness=0.14, emission=(0.45, 0.78, 1.0), emission_strength=0.35)
    ice = make_mat("IceCrystal", (0.18, 0.68, 1.0), metallic=0.15, roughness=0.08, emission=(0.20, 0.65, 1.0), emission_strength=0.65)

    for i in range(3):
        ang = i * 60
        add_beveled_cube(f"Arm{i}", (0.12, 1.72, 0.16), (0, 0, 0.05), (0, 0, ang), 0.03, ice)
        for sign in (-1, 1):
            rad = math.radians(ang + 90)
            px = math.cos(rad) * 0.52 * sign
            py = math.sin(rad) * 0.52 * sign
            add_beveled_cube(f"TipA{i}_{sign}", (0.09, 0.40, 0.14), (px, py, 0.08), (0, 0, ang + 45), 0.02, silver)
            add_beveled_cube(f"TipB{i}_{sign}", (0.09, 0.40, 0.14), (px, py, 0.08), (0, 0, ang - 45), 0.02, silver)

    bpy.ops.mesh.primitive_cylinder_add(vertices=6, radius=0.32, depth=0.24, location=(0, 0, 0.14))
    hub = bpy.context.active_object
    hub.data.materials.append(silver)
    render_to("suit_blue.png")


def build_suit_green():
    clear_meshes()
    gold = make_mat("Gold", (0.98, 0.78, 0.24), metallic=0.92, roughness=0.16)
    emerald = make_mat("Emerald", (0.08, 0.78, 0.36), metallic=0.15, roughness=0.12, emission=(0.05, 0.52, 0.20), emission_strength=0.38)

    positions = [(0, 0.38, 0.10), (-0.36, -0.14, 0.08), (0.36, -0.14, 0.08)]
    for pos in positions:
        bpy.ops.mesh.primitive_uv_sphere_add(segments=40, ring_count=24, radius=0.41, location=pos)
        leaf = bpy.context.active_object
        leaf.scale = (1.0, 1.05, 0.45)
        leaf.data.materials.append(emerald)
        smooth(leaf)

    add_beveled_cube("Stem", (0.14, 0.66, 0.14), (0, -0.46, 0.04), (0, 0, 0), 0.03, gold)
    bpy.ops.mesh.primitive_torus_add(major_radius=0.88, minor_radius=0.055, major_segments=64, minor_segments=24, location=(0, 0, -0.06))
    ring = bpy.context.active_object
    ring.data.materials.append(gold)
    smooth(ring)
    render_to("suit_green.png")


def build_suit_yellow():
    clear_meshes()
    gold = make_mat("SunGold", (1.0, 0.76, 0.12), metallic=0.82, roughness=0.16, emission=(0.95, 0.65, 0.08), emission_strength=0.40)
    core = make_mat("SunCore", (1.0, 0.92, 0.36), metallic=0.25, roughness=0.12, emission=(1.0, 0.85, 0.22), emission_strength=1.0)

    for i in range(8):
        rad = math.radians(i * 45)
        px = math.cos(rad) * 0.74
        py = math.sin(rad) * 0.74
        bpy.ops.mesh.primitive_cone_add(vertices=4, radius1=0.19, radius2=0.0, depth=0.48, location=(px, py, 0.08))
        ray = bpy.context.active_object
        ray.rotation_euler = Euler((math.radians(-90), 0, rad - math.pi / 2), 'XYZ')
        ray.scale = (1.0, 0.55, 1.0)
        ray.data.materials.append(gold)

    bpy.ops.mesh.primitive_uv_sphere_add(segments=48, ring_count=28, radius=0.46, location=(0, 0, 0.10))
    sun = bpy.context.active_object
    sun.scale = (1.0, 1.0, 0.45)
    sun.data.materials.append(core)
    smooth(sun)
    render_to("suit_yellow.png")


def build_special_wizard():
    clear_meshes()
    violet = make_mat("ArcaneViolet", (0.45, 0.18, 0.92), metallic=0.25, roughness=0.18, emission=(0.38, 0.14, 0.84), emission_strength=0.42)
    gold = make_mat("MagicGold", (1.0, 0.80, 0.20), metallic=0.92, roughness=0.15, emission=(1.0, 0.75, 0.12), emission_strength=0.55)

    # Outer magic ring
    bpy.ops.mesh.primitive_torus_add(major_radius=0.88, minor_radius=0.05, major_segments=64, minor_segments=24, location=(0, 0, -0.10))
    ring = bpy.context.active_object
    ring.data.materials.append(gold)
    smooth(ring)

    # Side-view Wizard Hat tilted slightly forward (-72 deg around X so tip points UP!)
    bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=0.74, depth=0.08, location=(0, -0.44, 0.05), rotation=(math.radians(-72), 0, 0))
    brim = bpy.context.active_object
    brim.data.materials.append(violet)
    smooth(brim)

    bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=0.43, depth=0.16, location=(0, -0.34, 0.10), rotation=(math.radians(-72), 0, 0))
    band = bpy.context.active_object
    band.data.materials.append(gold)
    smooth(band)

    # Pointed wizard cone pointing cleanly UP-RIGHT
    bpy.ops.mesh.primitive_cone_add(vertices=48, radius1=0.42, radius2=0.03, depth=1.18, location=(0.06, 0.14, 0.20), rotation=(math.radians(-72), math.radians(-12), 0))
    cone = bpy.context.active_object
    cone.data.materials.append(violet)
    smooth(cone)

    # Glowing 3D golden magic star near tip
    for r_ang in (0, 45):
        add_beveled_cube(f"Star{r_ang}", (0.28, 0.28, 0.12), (-0.42, 0.44, 0.36), (0, 0, r_ang), 0.02, gold)

    render_to("special_wizard.png")


def build_special_jester():
    clear_meshes()
    teal = make_mat("JesterTeal", (0.06, 0.68, 0.66), metallic=0.22, roughness=0.20, emission=(0.06, 0.45, 0.45), emission_strength=0.35)
    gold = make_mat("JesterGold", (1.0, 0.80, 0.22), metallic=0.92, roughness=0.15)
    crimson = make_mat("JesterCrimson", (0.90, 0.20, 0.34), metallic=0.22, roughness=0.20, emission=(0.45, 0.08, 0.14), emission_strength=0.2)

    bpy.ops.mesh.primitive_torus_add(major_radius=0.52, minor_radius=0.10, major_segments=56, minor_segments=24, location=(0, -0.34, 0.12), rotation=(math.radians(68), 0, 0))
    crown = bpy.context.active_object
    crown.data.materials.append(gold)
    smooth(crown)

    horns = [
        ((-0.44, 0.12, 0.18), (45, 0, 32), teal, (-0.72, 0.42, 0.24)),
        ((0.0, 0.28, 0.25), (40, 0, 0), gold, (0.0, 0.68, 0.30)),
        ((0.44, 0.12, 0.18), (45, 0, -32), crimson, (0.72, 0.42, 0.24)),
    ]
    for loc, rot, mat, bell_loc in horns:
        bpy.ops.mesh.primitive_cone_add(vertices=36, radius1=0.23, radius2=0.06, depth=0.78, location=loc, rotation=[math.radians(a) for a in rot])
        h = bpy.context.active_object
        h.data.materials.append(mat)
        smooth(h)
        bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=20, radius=0.14, location=bell_loc)
        b = bpy.context.active_object
        b.data.materials.append(gold)
        smooth(b)

    render_to("special_jester.png")


def build_card_back():
    clear_meshes()
    _, cam = setup_render(384, 540, transparent=True)
    cam.ortho_scale = 2.60

    indigo = make_mat("CardBackIndigo", (0.04, 0.06, 0.19), metallic=0.30, roughness=0.28)
    gold = make_mat("CardBackGold", (0.98, 0.78, 0.24), metallic=0.92, roughness=0.16, emission=(0.85, 0.60, 0.12), emission_strength=0.28)
    gem_mat = make_mat("CardGem", (0.58, 0.26, 0.98), metallic=0.15, roughness=0.10, emission=(0.55, 0.22, 0.98), emission_strength=1.1)

    add_beveled_cube("CardBase", (1.76, 2.52, 0.08), (0, 0, 0), (0, 0, 0), 0.07, indigo)
    add_beveled_cube("BorderTop", (1.58, 0.055, 0.11), (0, 1.12, 0.02), (0, 0, 0), 0.015, gold)
    add_beveled_cube("BorderBot", (1.58, 0.055, 0.11), (0, -1.12, 0.02), (0, 0, 0), 0.015, gold)
    add_beveled_cube("BorderL", (0.055, 2.28, 0.11), (-0.76, 0, 0.02), (0, 0, 0), 0.015, gold)
    add_beveled_cube("BorderR", (0.055, 2.28, 0.11), (0.76, 0, 0.02), (0, 0, 0), 0.015, gold)

    for r, minor in [(0.56, 0.032), (0.38, 0.022)]:
        bpy.ops.mesh.primitive_torus_add(major_radius=r, minor_radius=minor, major_segments=64, minor_segments=20, location=(0, 0, 0.06))
        t = bpy.context.active_object
        t.data.materials.append(gold)
        smooth(t)

    for ang in (0, 45):
        add_beveled_cube(f"Star{ang}", (0.46, 0.46, 0.06), (0, 0, 0.08), (0, 0, ang), 0.02, gold)

    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=0.17, location=(0, 0, 0.12))
    gem = bpy.context.active_object
    gem.data.materials.append(gem_mat)
    smooth(gem)

    render_to("card_back.png")


def build_table_crest():
    clear_meshes()
    _, cam = setup_render(512, 512, transparent=True)
    cam.ortho_scale = 2.6

    gold = make_mat("CrestGold", (0.96, 0.76, 0.24), metallic=0.90, roughness=0.22, emission=(0.80, 0.58, 0.14), emission_strength=0.25)
    for r, minor in [(1.08, 0.028), (0.78, 0.018)]:
        bpy.ops.mesh.primitive_torus_add(major_radius=r, minor_radius=minor, major_segments=72, minor_segments=20, location=(0, 0, 0))
        t = bpy.context.active_object
        t.data.materials.append(gold)
        smooth(t)
    for i in range(4):
        add_beveled_cube(f"Compass{i}", (0.04, 1.9, 0.04), (0, 0, 0.02), (0, 0, i * 45), 0.01, gold)
    render_to("table_crest.png")


def main():
    clear_scene()
    setup_render(256, 256, transparent=True)
    build_suit_red()
    build_suit_blue()
    build_suit_green()
    build_suit_yellow()
    build_special_wizard()
    build_special_jester()
    build_card_back()
    build_table_crest()
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
    print("Refined Blender card assets rendered successfully!")


if __name__ == "__main__":
    main()
