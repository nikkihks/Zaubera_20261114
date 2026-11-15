import math
import os
import random
import bpy
from mathutils import Euler, Vector

WORKSPACE = r"c:\Users\nicol\OneDrive - studmail.w-hs.de\Antigravity_Projekte\06_Zaubera"
UI_DIR = os.path.join(WORKSPACE, "assets", "ui")
CARDS_DIR = os.path.join(WORKSPACE, "assets", "cards")
BLEND_PATH = os.path.join(WORKSPACE, "assets", "blender", "wizard_theme.blend")
os.makedirs(UI_DIR, exist_ok=True)
os.makedirs(CARDS_DIR, exist_ok=True)


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def setup_scene(res_x, res_y, transparent=True, ortho_scale=2.4):
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
    if hasattr(scene, "eevee"):
        try:
            scene.eevee.taa_render_samples = 32
        except Exception:
            pass

    world = bpy.data.worlds.new("CampfireWorld")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (0.04, 0.03, 0.06, 1.0)
    bg.inputs["Strength"].default_value = 0.9

    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = ortho_scale
    cam_obj = bpy.data.objects.new("Cam", cam_data)
    bpy.context.collection.objects.link(cam_obj)
    cam_obj.location = (0, 0, 5.0)
    cam_obj.rotation_euler = (0, 0, 0)
    scene.camera = cam_obj
    return scene, cam_obj, cam_data


def add_light(name, ltype, loc, rot_deg, energy, color=(1, 1, 1), size=3.0):
    ldata = bpy.data.lights.new(name=name, type=ltype)
    ldata.energy = energy
    ldata.color = color
    if hasattr(ldata, "size"):
        ldata.size = size
    elif hasattr(ldata, "shadow_soft_size"):
        ldata.shadow_soft_size = size
    lobj = bpy.data.objects.new(name, ldata)
    bpy.context.collection.objects.link(lobj)
    lobj.location = loc
    lobj.rotation_euler = Euler([math.radians(a) for a in rot_deg], 'XYZ')
    return lobj


def clear_meshes_and_lights():
    for obj in list(bpy.data.objects):
        if obj.type in ("MESH", "LIGHT", "CURVE"):
            bpy.data.objects.remove(obj, do_unlink=True)


def set_smooth(obj):
    if obj and obj.type == "MESH":
        for p in obj.data.polygons:
            p.use_smooth = True


def make_wood_material(name="CarvedOakWood", dark=(0.09, 0.045, 0.02), light=(0.24, 0.12, 0.05), scale=10.0, bump_strength=0.18, roughness=0.45):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    texcoord = nt.nodes.new("ShaderNodeTexCoord")
    mapping = nt.nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (6.0, 0.65, 1.5)
    nt.links.new(texcoord.outputs["Object"], mapping.inputs["Vector"])

    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = scale
    noise.inputs["Detail"].default_value = 12.0
    noise.inputs["Roughness"].default_value = 0.62
    noise.inputs["Distortion"].default_value = 0.8
    nt.links.new(mapping.outputs["Vector"], noise.inputs["Vector"])

    wave = nt.nodes.new("ShaderNodeTexWave")
    wave.wave_type = "BANDS"
    wave.bands_direction = "X"
    wave.inputs["Scale"].default_value = 2.6
    wave.inputs["Distortion"].default_value = 3.2
    wave.inputs["Detail"].default_value = 5.0
    nt.links.new(mapping.outputs["Vector"], wave.inputs["Vector"])

    mix_val = nt.nodes.new("ShaderNodeMix")
    mix_val.data_type = "FLOAT"
    mix_val.inputs["Factor"].default_value = 0.55
    nt.links.new(wave.outputs["Fac"], mix_val.inputs[2])
    nt.links.new(noise.outputs["Fac"], mix_val.inputs[3])

    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.18
    ramp.color_ramp.elements[0].color = (*dark, 1.0)
    ramp.color_ramp.elements[1].position = 0.85
    ramp.color_ramp.elements[1].color = (*light, 1.0)
    nt.links.new(mix_val.outputs[0], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])

    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = 0.05

    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = bump_strength
    nt.links.new(mix_val.outputs[0], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def make_metal_material(name, base_color=(0.86, 0.65, 0.24), metallic=0.92, roughness=0.26, emission=None, emission_strength=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*base_color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if emission is not None and "Emission Color" in bsdf.inputs:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    return mat


def make_papyrus_material(name="TatteredPapyrus", light=(0.96, 0.88, 0.69), mid=(0.86, 0.73, 0.50), edge_dark=(0.48, 0.32, 0.17)):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    texcoord = nt.nodes.new("ShaderNodeTexCoord")

    # Fine isotropic parchment grain + organic blotches using Object space (prevents aspect stretching!)
    noise_blotch = nt.nodes.new("ShaderNodeTexNoise")
    noise_blotch.inputs["Scale"].default_value = 3.2
    noise_blotch.inputs["Detail"].default_value = 8.0
    noise_blotch.inputs["Roughness"].default_value = 0.65
    nt.links.new(texcoord.outputs["Object"], noise_blotch.inputs["Vector"])

    noise_fiber = nt.nodes.new("ShaderNodeTexNoise")
    noise_fiber.inputs["Scale"].default_value = 26.0
    noise_fiber.inputs["Detail"].default_value = 12.0
    noise_fiber.inputs["Roughness"].default_value = 0.82
    nt.links.new(texcoord.outputs["Object"], noise_fiber.inputs["Vector"])

    # Compute charred/aged border darkening from distance to generated center (0.5, 0.5)
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(texcoord.outputs["Generated"], sep.inputs["Vector"])

    sub_x = nt.nodes.new("ShaderNodeMath")
    sub_x.operation = "SUBTRACT"
    sub_x.inputs[1].default_value = 0.5
    nt.links.new(sep.outputs["X"], sub_x.inputs[0])

    abs_x = nt.nodes.new("ShaderNodeMath")
    abs_x.operation = "ABSOLUTE"
    nt.links.new(sub_x.outputs["Value"], abs_x.inputs[0])

    mul_x = nt.nodes.new("ShaderNodeMath")
    mul_x.operation = "MULTIPLY"
    mul_x.inputs[1].default_value = 2.0
    nt.links.new(abs_x.outputs["Value"], mul_x.inputs[0])

    sub_y = nt.nodes.new("ShaderNodeMath")
    sub_y.operation = "SUBTRACT"
    sub_y.inputs[1].default_value = 0.5
    nt.links.new(sep.outputs["Y"], sub_y.inputs[0])

    abs_y = nt.nodes.new("ShaderNodeMath")
    abs_y.operation = "ABSOLUTE"
    nt.links.new(sub_y.outputs["Value"], abs_y.inputs[0])

    mul_y = nt.nodes.new("ShaderNodeMath")
    mul_y.operation = "MULTIPLY"
    mul_y.inputs[1].default_value = 2.0
    nt.links.new(abs_y.outputs["Value"], mul_y.inputs[0])

    max_edge = nt.nodes.new("ShaderNodeMath")
    max_edge.operation = "MAXIMUM"
    nt.links.new(mul_x.outputs["Value"], max_edge.inputs[0])
    nt.links.new(mul_y.outputs["Value"], max_edge.inputs[1])

    # Add noise to charred edge
    edge_plus = nt.nodes.new("ShaderNodeMath")
    edge_plus.operation = "ADD"
    nt.links.new(max_edge.outputs["Value"], edge_plus.inputs[0])
    noise_scaled = nt.nodes.new("ShaderNodeMath")
    noise_scaled.operation = "MULTIPLY"
    noise_scaled.inputs[1].default_value = 0.22
    nt.links.new(noise_blotch.outputs["Fac"], noise_scaled.inputs[0])
    nt.links.new(noise_scaled.outputs["Value"], edge_plus.inputs[1])

    paper_ramp = nt.nodes.new("ShaderNodeValToRGB")
    paper_ramp.color_ramp.elements[0].position = 0.28
    paper_ramp.color_ramp.elements[0].color = (*light, 1.0)
    paper_ramp.color_ramp.elements[1].position = 0.72
    paper_ramp.color_ramp.elements[1].color = (*mid, 1.0)
    nt.links.new(noise_blotch.outputs["Fac"], paper_ramp.inputs["Fac"])

    burn_ramp = nt.nodes.new("ShaderNodeValToRGB")
    burn_ramp.color_ramp.elements[0].position = 0.86
    burn_ramp.color_ramp.elements[0].color = (0.0, 0.0, 0.0, 1.0)
    burn_ramp.color_ramp.elements[1].position = 1.05
    burn_ramp.color_ramp.elements[1].color = (1.0, 1.0, 1.0, 1.0)
    nt.links.new(edge_plus.outputs["Value"], burn_ramp.inputs["Fac"])

    mix_col = nt.nodes.new("ShaderNodeMix")
    mix_col.data_type = "RGBA"
    nt.links.new(burn_ramp.outputs["Color"], mix_col.inputs["Factor"])
    nt.links.new(paper_ramp.outputs["Color"], mix_col.inputs[6])
    mix_col.inputs[7].default_value = (*edge_dark, 1.0)
    nt.links.new(mix_col.outputs[2], bsdf.inputs["Base Color"])

    bsdf.inputs["Roughness"].default_value = 0.88
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.25
    nt.links.new(noise_fiber.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def add_rounded_rect_ring(name, outer_w, outer_h, inner_w, inner_h, thickness, radius_outer, radius_inner, mat):
    # Construct extruded carved rectangular frame with hole via 2D spline curves
    curve_data = bpy.data.curves.new(name + "_curve", type="CURVE")
    curve_data.dimensions = "2D"
    curve_data.fill_mode = "BOTH"
    curve_data.extrude = thickness * 0.5
    curve_data.bevel_depth = 0.022
    curve_data.bevel_resolution = 4

    def add_rounded_loop(w, h, r, clockwise=False):
        sp = curve_data.splines.new("POLY")
        pts = []
        hw = w * 0.5
        hh = h * 0.5
        corners = [
            (hw - r, hh - r, 0.0, math.pi * 0.5),
            (-hw + r, hh - r, math.pi * 0.5, math.pi),
            (-hw + r, -hh + r, math.pi, math.pi * 1.5),
            (hw - r, -hh + r, math.pi * 1.5, math.tau),
        ]
        segs = 8
        for cx, cy, a0, a1 in corners:
            for i in range(segs + 1):
                a = a0 + (a1 - a0) * (i / segs)
                pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
        if clockwise:
            pts.reverse()
        sp.points.add(len(pts) - 1)
        for i, (px, py) in enumerate(pts):
            sp.points[i].co = (px, py, 0.0, 1.0)
        sp.use_cyclic_u = True

    add_rounded_loop(outer_w, outer_h, radius_outer, clockwise=False)
    add_rounded_loop(inner_w, inner_h, radius_inner, clockwise=True)

    obj = bpy.data.objects.new(name, curve_data)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    return obj


def build_wood_card_frame():
    clear_meshes_and_lights()
    scene, cam_obj, _cam = setup_scene(512, 736, transparent=True, ortho_scale=2.88)
    # Warm campfire top-right key + cool rim so oak bevels gleam
    add_light("Key", "AREA", (1.6, -1.8, 3.8), (22, 18, 0), 220.0, (1.0, 0.84, 0.62), 2.5)
    add_light("Rim", "AREA", (-1.8, 2.0, 3.2), (-24, -22, 0), 140.0, (0.72, 0.85, 1.0), 2.8)
    add_light("Fill", "AREA", (0.0, 0.0, 4.5), (0, 0, 0), 55.0, (1.0, 0.92, 0.82), 4.0)

    oak_mat = make_wood_material("CardOak", dark=(0.11, 0.055, 0.025), light=(0.28, 0.145, 0.065), scale=8.5, bump_strength=0.22, roughness=0.40)
    brass_mat = make_metal_material("CardBrass", base_color=(0.88, 0.68, 0.25), metallic=0.92, roughness=0.24)
    gold_inlay = make_metal_material("GoldInlay", base_color=(0.95, 0.78, 0.32), metallic=0.88, roughness=0.20, emission=(0.95, 0.68, 0.2), emission_strength=0.12)

    # Outer carved walnut/oak frame (ratio 512 / 736 = 2.0 / 2.875)
    w_out, h_out = 1.94, 2.80
    w_in, h_in = 1.72, 2.58
    add_rounded_rect_ring("WoodOuterFrame", w_out, h_out, w_in, h_in, 0.11, 0.18, 0.11, oak_mat)

    # Thin recessed brass inlay trim inside frame opening
    inlay = add_rounded_rect_ring("BrassTrim", w_in + 0.035, h_in + 0.035, w_in - 0.015, h_in - 0.015, 0.03, 0.12, 0.10, gold_inlay)
    inlay.location.z = 0.045

    # Corner brass rivets/medallions
    for sx in (-1, 1):
        for sy in (-1, 1):
            bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=10, radius=0.042, location=(sx * 0.855, sy * 1.285, 0.068))
            riv = bpy.context.active_object
            riv.scale = (1.0, 1.0, 0.55)
            set_smooth(riv)
            riv.data.materials.append(brass_mat)

    scene.render.filepath = os.path.join(UI_DIR, "wood_card_frame.png")
    bpy.ops.render.render(write_still=True)


def build_papyrus_slab(filename, res_x, res_y, ortho_x, light_col, mid_col, edge_col, width, height, seed=42):
    clear_meshes_and_lights()
    rng = random.Random(seed)
    scene, cam_obj, _cam = setup_scene(res_x, res_y, transparent=True, ortho_scale=ortho_x)
    add_light("WarmKey", "AREA", (1.2, -1.6, 3.8), (18, 12, 0), 230.0, (1.0, 0.90, 0.72), 3.4)
    add_light("Rim", "AREA", (-1.5, 1.4, 3.2), (-20, -18, 0), 95.0, (0.95, 0.80, 0.60), 3.0)

    # Dense grid mesh sculpted with jagged torn edges and parchment ripple
    nx, ny = 64, 24
    mesh = bpy.data.meshes.new("PapyrusMesh")
    obj = bpy.data.objects.new("PapyrusSlab", mesh)
    bpy.context.collection.objects.link(obj)

    verts = []
    faces = []
    hw = width * 0.5
    hh = height * 0.5

    # Deterministic fractal edge displacement per edge coordinate
    def jagged(t, freq1, freq2, amp):
        return (
            math.sin(t * freq1 + seed) * 0.45
            + math.cos(t * freq2 + seed * 1.7) * 0.35
            + rng.uniform(-0.35, 0.35)
        ) * amp

    for j in range(ny + 1):
        v = j / ny
        y_base = -hh + v * height
        # Subtle edge inward notch near corners + horizontal deckle tears
        for i in range(nx + 1):
            u = i / nx
            x_base = -hw + u * width

            # Edge distance factor (1 at boundary, 0 inside)
            edge_x = max(0.0, abs(u - 0.5) * 2.0 - 0.82) / 0.18
            edge_y = max(0.0, abs(v - 0.5) * 2.0 - 0.74) / 0.26

            x = x_base
            y = y_base
            if edge_x > 0.0:
                notch = jagged(v * 6.0, 7.0, 17.0, 0.075)
                x -= math.copysign(1.0, u - 0.5) * edge_x * abs(notch)
                if rng.random() < 0.08 and edge_x > 0.7:
                    x -= math.copysign(0.045, u - 0.5)
            if edge_y > 0.0:
                notch_y = jagged(u * 10.0, 9.0, 23.0, 0.055)
                y -= math.copysign(1.0, v - 0.5) * edge_y * abs(notch_y)
                if rng.random() < 0.09 and edge_y > 0.7:
                    y -= math.copysign(0.035, v - 0.5)

            # Subtle natural parchment wave curl in Z
            z = (
                math.sin(u * math.pi * 2.5) * 0.018
                + math.cos(v * math.pi * 2.0) * 0.014
                + 0.025 * max(edge_x, edge_y)
            )
            verts.append((x, y, z))

    for j in range(ny):
        for i in range(nx):
            a = j * (nx + 1) + i
            b = a + 1
            c = a + (nx + 1) + 1
            d = a + (nx + 1)
            faces.append((a, b, c, d))

    mesh.from_pydata(verts, [], faces)
    mesh.update()
    set_smooth(obj)

    mat = make_papyrus_material("Papyrus_" + filename, light=light_col, mid=mid_col, edge_dark=edge_col)
    obj.data.materials.append(mat)

    # Corner small wax/stitch tack accents? No — keep slab clean for crisp readable text contrast!
    scene.render.filepath = os.path.join(UI_DIR, filename)
    bpy.ops.render.render(write_still=True)


def build_arcane_rune_ring():
    clear_meshes_and_lights()
    scene, cam_obj, _cam = setup_scene(768, 768, transparent=True, ortho_scale=2.55)
    add_light("FireKey", "AREA", (1.8, -1.8, 3.6), (25, 22, 0), 220.0, (1.0, 0.72, 0.35), 2.5)
    add_light("ArcaneRim", "AREA", (-1.8, 1.8, 3.6), (-25, -22, 0), 170.0, (0.35, 0.80, 1.0), 2.6)

    obsidian_mat = make_metal_material("RuneStone", base_color=(0.04, 0.05, 0.09), metallic=0.45, roughness=0.38)
    bronze_mat = make_metal_material("RuneBronze", base_color=(0.68, 0.44, 0.16), metallic=0.88, roughness=0.28)
    gold_mat = make_metal_material("RuneGold", base_color=(0.95, 0.72, 0.22), metallic=0.92, roughness=0.20, emission=(0.92, 0.56, 0.10), emission_strength=0.55)
    glow_amber = make_metal_material("GlowAmber", base_color=(1.0, 0.55, 0.08), metallic=0.05, roughness=0.2, emission=(1.0, 0.52, 0.06), emission_strength=1.55)
    glow_cyan = make_metal_material("GlowCyan", base_color=(0.12, 0.78, 0.98), metallic=0.05, roughness=0.2, emission=(0.10, 0.76, 1.0), emission_strength=1.45)

    # Subtle translucent dark obsidian ring bed so engraved gold/cyan runes ALWAYS read clearly!
    bpy.ops.mesh.primitive_cylinder_add(vertices=64, radius=1.08, depth=0.015, location=(0, 0, -0.02))
    disc = bpy.context.active_object
    disc_mat = bpy.data.materials.new("RuneDisc")
    disc_mat.use_nodes = True
    bsdf = disc_mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (0.04, 0.05, 0.08, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.6
    if "Alpha" in bsdf.inputs:
        bsdf.inputs["Alpha"].default_value = 0.62
    disc.data.materials.append(disc_mat)

    # Carved outer obsidian ring + bronze trim
    bpy.ops.mesh.primitive_torus_add(major_radius=1.04, minor_radius=0.06, major_segments=64, minor_segments=16, location=(0, 0, 0.0))
    t_out = bpy.context.active_object
    t_out.scale.z = 0.45
    set_smooth(t_out)
    t_out.data.materials.append(obsidian_mat)

    for r, minor, m in [(1.04, 0.018, glow_amber), (0.85, 0.024, gold_mat), (0.62, 0.016, glow_cyan), (0.34, 0.014, glow_amber)]:
        bpy.ops.mesh.primitive_torus_add(major_radius=r, minor_radius=minor, major_segments=64, minor_segments=12, location=(0, 0, 0.025))
        t = bpy.context.active_object
        set_smooth(t)
        t.data.materials.append(m)

    # 12 glowing rune talisman plates between outer & middle rings
    for k in range(12):
        ang = k * (math.tau / 12.0)
        rx = math.cos(ang) * 0.945
        ry = math.sin(ang) * 0.945
        bpy.ops.mesh.primitive_cube_add(size=0.072, location=(rx, ry, 0.032), rotation=(0, 0, ang))
        glyph = bpy.context.active_object
        glyph.scale = (0.48, 1.15, 0.35)
        glyph.data.materials.append(glow_amber if k % 2 == 0 else glow_cyan)

    # 8-point sculpted golden star spikes & central hearth ember medallion
    for k in range(8):
        ang = k * (math.tau / 8.0)
        dist = 0.56 if k % 2 == 0 else 0.46
        depth = 0.44 if k % 2 == 0 else 0.28
        rx = math.cos(ang) * dist
        ry = math.sin(ang) * dist
        bpy.ops.mesh.primitive_cone_add(vertices=4, radius1=0.048, depth=depth, location=(rx, ry, 0.025))
        sp = bpy.context.active_object
        sp.rotation_euler = (math.pi * 0.5, 0, ang - math.pi * 0.5)
        sp.scale.y = 0.25
        sp.data.materials.append(gold_mat if k % 2 == 0 else bronze_mat)

    bpy.ops.mesh.primitive_torus_add(major_radius=0.14, minor_radius=0.022, major_segments=32, minor_segments=10, location=(0, 0, 0.028))
    ring_c = bpy.context.active_object
    ring_c.data.materials.append(gold_mat)
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=0.09, location=(0, 0, 0.032))
    core = bpy.context.active_object
    core.scale = (1.0, 1.0, 0.35)
    core.data.materials.append(glow_amber)

    scene.render.filepath = os.path.join(UI_DIR, "arcane_rune_ring.png")
    bpy.ops.render.render(write_still=True)


def build_campfire_table_bg():
    clear_meshes_and_lights()
    # 720x1280 portrait -> aspect 0.5625; camera ortho_scale maps vertical if portrait?
    # Note: in Blender ortho_scale maps the larger dimension unless sensor_fit="VERTICAL"
    scene, cam_obj, cam_data = setup_scene(720, 1280, transparent=False, ortho_scale=3.2)
    cam_data.sensor_fit = "VERTICAL"
    cam_obj.location = (0, 0, 5.0)
    scene.world.node_tree.nodes.get("Background").inputs["Color"].default_value = (0.015, 0.018, 0.035, 1.0)
    scene.world.node_tree.nodes.get("Background").inputs["Strength"].default_value = 0.35

    plank_mat = make_wood_material("CampfireOakPlanks", dark=(0.035, 0.020, 0.012), light=(0.14, 0.072, 0.032), scale=7.0, bump_strength=0.32, roughness=0.58)
    trim_mat = make_metal_material("TableTrim", base_color=(0.04, 0.025, 0.018), metallic=0.15, roughness=0.75)

    # Build vertical dark weathered wooden planks across full 9:16 portrait view
    num_planks = 9
    plank_w = 2.0 / num_planks
    for i in range(num_planks):
        px = -1.0 + (i + 0.5) * plank_w
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(px, 0.0, (i % 2) * 0.004))
        p = bpy.context.active_object
        p.scale = (plank_w * 0.985, 3.4, 0.08)
        p.data.materials.append(plank_mat)

    # Subtle carved dark stone border ring on table around center arena
    bpy.ops.mesh.primitive_torus_add(major_radius=0.72, minor_radius=0.02, major_segments=64, minor_segments=10, location=(0, 0.05, 0.04))
    r = bpy.context.active_object
    r.data.materials.append(trim_mat)

    # Warm flickering campfire point lights illuminating center-mid, fading to deep darkness around edges!
    add_light("CampfireCore", "POINT", (0.0, 0.08, 0.42), (0, 0, 0), 18.0, (1.0, 0.48, 0.14), 0.28)
    add_light("CampfireWarmBounce", "POINT", (0.08, 0.10, 0.85), (0, 0, 0), 13.0, (1.0, 0.65, 0.28), 0.65)
    # Cool faint moonlight kiss only on very distant perimeter
    add_light("MoonFill", "AREA", (-1.5, 2.2, 2.8), (-30, -20, 0), 3.0, (0.20, 0.35, 0.80), 2.5)
    # Suppress shadow harshness if needed; keep dramatic vignette!
    scene.render.filepath = os.path.join(UI_DIR, "campfire_table_bg.png")
    bpy.ops.render.render(write_still=True)


def build_wooden_card_back():
    clear_meshes_and_lights()
    scene, cam_obj, _cam = setup_scene(512, 736, transparent=True, ortho_scale=2.88)
    add_light("Key", "AREA", (1.6, -1.8, 3.8), (22, 18, 0), 210.0, (1.0, 0.86, 0.65), 2.5)
    add_light("Rim", "AREA", (-1.8, 2.0, 3.2), (-24, -22, 0), 135.0, (0.65, 0.82, 1.0), 2.8)

    oak_mat = make_wood_material("BackOak", dark=(0.07, 0.035, 0.015), light=(0.20, 0.10, 0.045), scale=9.0, bump_strength=0.20, roughness=0.44)
    gold_mat = make_metal_material("BackGold", base_color=(0.90, 0.68, 0.24), metallic=0.90, roughness=0.24, emission=(0.85, 0.55, 0.12), emission_strength=0.22)
    glow_cyan = make_metal_material("BackCyan", base_color=(0.12, 0.78, 0.96), metallic=0.15, roughness=0.18, emission=(0.10, 0.72, 0.95), emission_strength=1.35)

    # Solid beveled oak backing plate (no inner hole!)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
    slab = bpy.context.active_object
    slab.scale = (1.92, 2.78, 0.09)
    bev = slab.modifiers.new("Bevel", "BEVEL")
    bev.width = 0.04
    bev.segments = 3
    set_smooth(slab)
    slab.data.materials.append(oak_mat)

    # Gold border inlay
    inlay = add_rounded_rect_ring("BackBorder", 1.72, 2.56, 1.66, 2.50, 0.03, 0.12, 0.10, gold_mat)
    inlay.location.z = 0.045
    # Central glowing compass star & sapphire medallion
    bpy.ops.mesh.primitive_torus_add(major_radius=0.42, minor_radius=0.022, major_segments=48, minor_segments=10, location=(0, 0, 0.055))
    t = bpy.context.active_object
    t.data.materials.append(gold_mat)
    for k in range(8):
        ang = k * (math.tau / 8.0)
        bpy.ops.mesh.primitive_cone_add(vertices=4, radius1=0.045, depth=0.30 if k % 2 == 0 else 0.18, location=(math.cos(ang) * 0.25, math.sin(ang) * 0.25, 0.056))
        sp = bpy.context.active_object
        sp.rotation_euler = (math.pi * 0.5, 0, ang - math.pi * 0.5)
        sp.scale.y = 0.28
        sp.data.materials.append(gold_mat)
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=0.11, location=(0, 0, 0.058))
    gem = bpy.context.active_object
    gem.scale = (1.0, 1.0, 0.35)
    gem.data.materials.append(glow_cyan)

    scene.render.filepath = os.path.join(CARDS_DIR, "card_back.png")
    bpy.ops.render.render(write_still=True)


def main():
    clear_scene()
    build_wood_card_frame()
    build_papyrus_slab(
        "papyrus_btn.png", 768, 128, 4.2,
        light_col=(0.98, 0.91, 0.72), mid_col=(0.89, 0.78, 0.56), edge_col=(0.56, 0.40, 0.22),
        width=4.08, height=0.66, seed=11
    )
    build_papyrus_slab(
        "papyrus_panel.png", 768, 512, 3.0,
        light_col=(0.19, 0.13, 0.08), mid_col=(0.13, 0.085, 0.055), edge_col=(0.055, 0.032, 0.02),
        width=2.84, height=1.88, seed=29
    )
    build_arcane_rune_ring()
    build_campfire_table_bg()
    build_wooden_card_back()
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
    print("THEME ASSETS GENERATED SUCCESSFULLY")


if __name__ == "__main__":
    main()
