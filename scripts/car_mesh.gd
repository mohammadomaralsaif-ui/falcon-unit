extends RefCounted
## Builds detailed vehicle meshes (sedans, taxis, police cars, SUVs, ambulances) from side profiles.
## Vehicles face +Z (Godot VehicleBody3D forward).

const CustomModels = preload("res://scripts/custom_models.gd")

const SPECS := {
	"sedan": {"L": 4.5, "W": 1.78, "belt": 1.0, "roof": 1.44, "r": 0.36, "wz": 1.4, "hood": 0.92, "ws0": 1.05, "ws1": 0.35, "re": -1.1, "rb": -1.9},
	"suv": {"L": 4.9, "W": 2.0, "belt": 1.25, "roof": 1.95, "r": 0.45, "wz": 1.55, "hood": 1.18, "ws0": 1.4, "ws1": 0.8, "re": -2.2, "rb": -2.36},
	"van": {"L": 5.4, "W": 2.05, "belt": 1.25, "roof": 2.55, "r": 0.42, "wz": 1.75, "hood": 1.2, "ws0": 2.1, "ws1": 1.65, "re": -2.6, "rb": -2.66},
}

static var _mats := {}

static func mat(key: String, color: Color, metal := 0.0, rough := 0.6, coat := false, emission := Color.BLACK, emis_e := 0.0) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metal
	m.roughness = rough
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if coat:
		m.clearcoat_enabled = true
		m.clearcoat = 1.0
		m.clearcoat_roughness = 0.08
	if emis_e > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = emis_e
	_mats[key] = m
	return m

static func extrude(poly: PackedVector2Array, width: float, x_off := 0.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tri := Geometry2D.triangulate_polygon(poly)
	var hw := width * 0.5
	for side in [-1.0, 1.0]:
		var x: float = side * hw + x_off
		for i in range(0, tri.size(), 3):
			var a := poly[tri[i]]
			var b := poly[tri[i + 1]]
			var c := poly[tri[i + 2]]
			if side > 0:
				st.add_vertex(Vector3(x, a.y, a.x)); st.add_vertex(Vector3(x, b.y, b.x)); st.add_vertex(Vector3(x, c.y, c.x))
			else:
				st.add_vertex(Vector3(x, a.y, a.x)); st.add_vertex(Vector3(x, c.y, c.x)); st.add_vertex(Vector3(x, b.y, b.x))
	var n := poly.size()
	for i in n:
		var p := poly[i]
		var q := poly[(i + 1) % n]
		var v0 := Vector3(-hw + x_off, p.y, p.x)
		var v1 := Vector3(hw + x_off, p.y, p.x)
		var v2 := Vector3(hw + x_off, q.y, q.x)
		var v3 := Vector3(-hw + x_off, q.y, q.x)
		st.add_vertex(v0); st.add_vertex(v1); st.add_vertex(v2)
		st.add_vertex(v0); st.add_vertex(v2); st.add_vertex(v3)
	st.generate_normals()
	st.index()
	return st.commit()

## Rounded extrusion: side profile (z, y) swept across the car width with rounded
## (bevelled) edges, tumblehome (narrower toward the top) and tapered nose / tail in plan view.
static func extrude_round(poly: PackedVector2Array, width: float, bev := 0.08, tumble := 0.0, y0 := 0.0, y1 := 1.0, taper := 0.0, hl := 2.5) -> ArrayMesh:
	var n := poly.size()
	var area := 0.0
	for i in n:
		area += poly[i].x * poly[(i + 1) % n].y - poly[(i + 1) % n].x * poly[i].y
	var wind := 1.0 if area > 0.0 else -1.0
	var hw := width * 0.5
	# outward 2D edge normals
	var en: Array[Vector2] = []
	for i in n:
		var d := (poly[(i + 1) % n] - poly[i]).normalized()
		en.append(Vector2(d.y, -d.x) * wind)
	var rings := []   # each: [P, inset offset, normal]
	var cap_pts := PackedVector2Array()
	for i in n:
		var n1: Vector2 = en[(i - 1 + n) % n]
		var n2: Vector2 = en[i]
		var c := n1.dot(n2)
		var P := poly[i]
		if c > 0.7:
			var nv := (n1 + n2).normalized()
			rings.append([P, nv * bev, nv])
			cap_pts.append(P - nv * bev)
		else:
			var m := (n1 + n2) / maxf(1.0 + c, 0.25)
			if m.length() > 2.0:
				m = m.normalized() * 2.0
			rings.append([P, m * bev, n1])
			rings.append([P, m * bev, n2])
			cap_pts.append(P - m * bev)
	var steps := 3
	var phis := []
	for k in steps + 1:
		phis.append(PI * 0.5 * k / steps)
	var f := func(v: Vector3) -> Vector3:
		var t := clampf((v.y - y0) / maxf(y1 - y0, 0.01), 0.0, 1.0)
		var e := clampf((absf(v.z) - hl * 0.7) / (hl * 0.3), 0.0, 1.0)
		return Vector3(v.x * (1.0 - tumble * t * t) * (1.0 - taper * e * e), v.y, v.z)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# ring vertex lists: across width from left (-x) to right (+x)
	var ring_verts := []
	for rg in rings:
		var P: Vector2 = rg[0]; var o: Vector2 = rg[1]; var nn: Vector2 = rg[2]
		var vs := []
		for side in [-1.0, 1.0]:
			var order := phis.duplicate()
			if side < 0:
				order.reverse()
			for ph in order:
				var q: Vector2 = P - o + nn * bev * cos(ph)
				var x: float = side * (hw - bev + bev * sin(ph))
				var pos: Vector3 = f.call(Vector3(x, q.y, q.x))
				var nor := Vector3(side * sin(ph), nn.y * cos(ph), nn.x * cos(ph)).normalized()
				vs.append([pos, nor])
		ring_verts.append(vs)
	var R := ring_verts.size()
	for i in R:
		var a: Array = ring_verts[i]
		var b: Array = ring_verts[(i + 1) % R]
		for k in a.size() - 1:
			var quad := [a[k], b[k], b[k + 1], a[k + 1]]
			for t in [[0, 1, 2], [0, 2, 3]]:
				_tri(st, quad[t[0]], quad[t[1]], quad[t[2]])
	# caps
	var tri := Geometry2D.triangulate_polygon(cap_pts)
	if tri.is_empty():
		tri = Geometry2D.triangulate_polygon(poly)
	for side in [-1.0, 1.0]:
		var x: float = side * hw
		for i in range(0, tri.size(), 3):
			var pts := []
			for id in [tri[i], tri[i + 1], tri[i + 2]]:
				var c2: Vector2 = cap_pts[id]
				pts.append([f.call(Vector3(x, c2.y, c2.x)), Vector3(side, 0, 0)])
			_tri(st, pts[0], pts[1], pts[2])
	st.index()
	return st.commit()

## Emits a triangle (vertices are [position, normal]) wound so its front face matches the normal.
static func _tri(st: SurfaceTool, a: Array, b: Array, c: Array) -> void:
	var g: Vector3 = (b[0] - a[0]).cross(c[0] - a[0])
	var nsum: Vector3 = a[1] + b[1] + c[1]
	if g.dot(nsum) > 0.0:   # Godot front faces are clockwise
		var t := b; b = c; c = t
	for v in [a, b, c]:
		st.set_normal(v[1]); st.add_vertex(v[0])

static func _arch(pts: PackedVector2Array, cz: float, base: float, r: float) -> void:
	for k in 13:
		var a := PI - PI * k / 12.0
		pts.append(Vector2(cz + cos(a) * r, base + sin(a) * r))

static func _box(parent: Node3D, size: Vector3, pos: Vector3, m: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi

static func _between(parent: Node3D, a: Vector3, b: Vector3, thick: Vector2, m: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(thick.x, thick.y, a.distance_to(b))
	mi.mesh = bm
	mi.material_override = m
	parent.add_child(mi)
	var d := (b - a).normalized()
	var up := Vector3.UP if absf(d.y) < 0.98 else Vector3.FORWARD
	mi.transform = Transform3D(Basis.looking_at(d, up), (a + b) * 0.5)

static func wheel(parent: Node3D, r: float, w: float) -> Node3D:
	var root := Node3D.new()
	var tire := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = r; tm.bottom_radius = r; tm.height = w; tm.radial_segments = 24
	tire.mesh = tm
	tire.rotation.z = PI / 2
	tire.material_override = mat("tire", Color(0.06, 0.06, 0.06), 0.0, 0.9)
	root.add_child(tire)
	var rim := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = r * 0.62; rm.bottom_radius = r * 0.62; rm.height = w * 1.04; rm.radial_segments = 20
	rim.mesh = rm
	rim.rotation.z = PI / 2
	rim.material_override = mat("rim", Color(0.72, 0.74, 0.76), 0.9, 0.3)
	root.add_child(rim)
	for i in 5:
		var sp := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = Vector3(w * 1.08, r * 1.15, 0.05)
		sp.mesh = sb
		sp.rotation.x = TAU * i / 5.0
		sp.material_override = mat("spoke", Color(0.55, 0.57, 0.6), 0.9, 0.35)
		root.add_child(sp)
	parent.add_child(root)
	return root

## kind: sedan | taxi | police | suv | swat | van(ambulance)
static func build(kind: String, color := Color(0.85, 0.85, 0.86), with_wheels := true) -> Node3D:
	var base_kind := "sedan"
	if kind == "suv" or kind == "swat":
		base_kind = "suv"
	elif kind == "ambulance" or kind == "cashvan":
		base_kind = "van"
	var s: Dictionary = SPECS[base_kind]
	# a real model dropped into assets/cars/ wins over the procedural one
	var real := CustomModels.car(kind, float(s.L), randi())
	if real:
		real.set_meta("flashers", {})
		real.set_meta("spec", s)
		return real
	var L: float = s.L; var W: float = s.W; var hl := L * 0.5; var r: float = s.r; var wz: float = s.wz
	var root := Node3D.new()
	if kind == "taxi":
		color = Color(0.95, 0.75, 0.12)
	elif kind == "police" or kind == "ambulance":
		color = Color(0.95, 0.95, 0.94)
	elif kind == "swat":
		color = Color(0.07, 0.11, 0.2)
	elif kind == "cashvan":
		color = Color(0.22, 0.27, 0.25)
	var paint := mat("paint_%s" % color.to_html(), color, 0.45, 0.32, true)
	var glass := mat("glass", Color(0.04, 0.06, 0.08), 0.6, 0.05, true)
	var dark := mat("dark", Color(0.07, 0.07, 0.08), 0.2, 0.6)
	var chrome := mat("chrome", Color(0.8, 0.8, 0.82), 1.0, 0.15)
	var base := 0.42
	# lower body
	var p := PackedVector2Array()
	p.append(Vector2(-hl, base))
	_arch(p, -wz, base, r + 0.04)
	_arch(p, wz, base, r + 0.04)
	p.append(Vector2(hl, base))
	p.append(Vector2(hl + 0.05, base + 0.25))
	p.append(Vector2(hl, s.hood - 0.04))
	p.append(Vector2(s.ws0, s.belt))
	p.append(Vector2(s.rb, s.belt))
	p.append(Vector2(-hl - 0.02, s.belt - 0.04))
	p.append(Vector2(-hl - 0.05, base + 0.2))
	var body := MeshInstance3D.new()
	body.mesh = extrude_round(p, W, 0.1, 0.06, base, s.belt, 0.07, hl)
	body.material_override = paint
	root.add_child(body)
	# glass cabin
	var g := PackedVector2Array([Vector2(s.ws0, s.belt), Vector2(s.ws1, s.roof - 0.02), Vector2(s.re, s.roof), Vector2(s.rb, s.belt)])
	var cab := MeshInstance3D.new()
	cab.mesh = extrude_round(g, W - 0.12, 0.08, 0.2, s.belt, s.roof, 0.0, hl)
	cab.material_override = glass
	root.add_child(cab)
	# roof slab
	var rf := PackedVector2Array([Vector2(s.ws1 - 0.05, s.roof - 0.03), Vector2(s.re + 0.02, s.roof - 0.01), Vector2(s.re + 0.04, s.roof + 0.05), Vector2(s.ws1 - 0.07, s.roof + 0.03)])
	var roof := MeshInstance3D.new()
	roof.mesh = extrude_round(rf, (W - 0.12) * 0.8 + 0.04, 0.03, 0.0, 0.0, 1.0, 0.0, hl)
	roof.material_override = paint
	root.add_child(roof)
	# pillars
	for sd in [-1.0, 1.0]:
		var x: float = sd * ((W - 0.12) * 0.5 + 0.005)
		var xt: float = sd * ((W - 0.12) * 0.4 + 0.005)
		_between(root, Vector3(x, s.belt, s.ws0), Vector3(xt, s.roof - 0.04, s.ws1 - 0.03), Vector2(0.07, 0.08), paint)
		_between(root, Vector3(x, s.belt, s.rb), Vector3(xt, s.roof - 0.04, s.re + 0.03), Vector2(0.07, 0.14), paint)
		var bz: float = lerpf(float(s.ws1), float(s.re), 0.48)
		_between(root, Vector3(x, s.belt, bz), Vector3(xt, s.roof - 0.04, bz), Vector2(0.07, 0.09), dark)
		_box(root, Vector3(0.07, 0.11, 0.16), Vector3(sd * (W * 0.5 + 0.06), s.belt + 0.03, s.ws0 - 0.15), paint)
		_box(root, Vector3(0.012, s.belt - base - 0.1, 0.012), Vector3(sd * (W * 0.5 + 0.004), (s.belt + base) * 0.5, bz), dark)
		_box(root, Vector3(0.02, 0.03, 0.14), Vector3(sd * (W * 0.5 + 0.01), s.belt - 0.12, bz + 0.45), chrome)
		_box(root, Vector3(0.02, 0.03, 0.14), Vector3(sd * (W * 0.5 + 0.01), s.belt - 0.12, bz - 0.55), chrome)
	# bumpers, grille, lights
	_box(root, Vector3(W * 0.98, 0.24, 0.2), Vector3(0, base + 0.12, hl + 0.02), dark)
	_box(root, Vector3(W * 0.98, 0.24, 0.2), Vector3(0, base + 0.14, -hl - 0.02), dark)
	_box(root, Vector3(W * 0.46, 0.16, 0.05), Vector3(0, s.hood - 0.18, hl + 0.04), mat("grille", Color(0.03, 0.03, 0.03), 0.7, 0.35))
	var hlm := mat("headlight", Color(1, 1, 0.95), 0.0, 0.2, false, Color(1, 0.96, 0.85), 2.5)
	var tlm := mat("taillight", Color(0.6, 0.02, 0.02), 0.0, 0.3, false, Color(1, 0.05, 0.03), 1.6)
	for sd in [-1.0, 1.0]:
		_box(root, Vector3(0.36, 0.13, 0.05), Vector3(sd * (W * 0.5 - 0.3), s.hood - 0.12, hl + 0.03), hlm)
		_box(root, Vector3(0.3, 0.12, 0.05), Vector3(sd * (W * 0.5 - 0.25), s.belt - 0.15, -hl - 0.03), tlm)
	# plates
	for z in [hl + 0.13, -hl - 0.13]:
		_box(root, Vector3(0.52, 0.13, 0.01), Vector3(0, base + 0.15, z), mat("plate", Color(0.95, 0.95, 0.93), 0.0, 0.4))
		var lbl := Label3D.new()
		lbl.text = "%d-%05d" % [randi_range(10, 90), randi_range(10000, 99999)]
		lbl.font_size = 22
		lbl.pixel_size = 0.004
		lbl.modulate = Color(0.05, 0.05, 0.05)
		lbl.outline_size = 0
		lbl.position = Vector3(0, base + 0.15, z + (0.008 if z > 0 else -0.008))
		if z < 0:
			lbl.rotation.y = PI
		root.add_child(lbl)
	# livery
	var fl := {}
	if kind == "taxi":
		_box(root, Vector3(0.6, 0.18, 0.26), Vector3(0, s.roof + 0.14, (s.ws1 + s.re) * 0.5), mat("taxisign", Color(0.15, 0.15, 0.15), 0.0, 0.5, false, Color(1, 0.85, 0.4), 1.2))
	if kind == "police" or kind == "swat" or kind == "ambulance":
		var band_col := Color(0.11, 0.25, 0.6) if kind != "ambulance" else Color(0.88, 0.32, 0.1)
		if kind == "swat":
			band_col = Color(0.92, 0.92, 0.92)
		for sd in [-1.0, 1.0]:
			_box(root, Vector3(0.02, 0.22, L * 0.72), Vector3(sd * (W * 0.5 + 0.012), base + 0.42, 0), mat("band_%s" % band_col.to_html(), band_col, 0.3, 0.4))
			var t := Label3D.new()
			t.text = "إسعاف" if kind == "ambulance" else "شرطة  POLICE"
			t.font = load("res://assets/fonts/Tajawal-Bold.ttf")
			t.font_size = 64
			t.pixel_size = 0.006
			t.modulate = Color(0.1, 0.15, 0.3) if kind != "ambulance" else Color(0.8, 0.15, 0.08)
			if kind == "swat":
				t.modulate = Color(0.95, 0.95, 0.95)
			t.outline_size = 0
			t.position = Vector3(sd * (W * 0.5 + 0.03), s.belt - 0.12, -0.2)
			t.rotation.y = sd * PI / 2
			root.add_child(t)
		var bar_y: float = s.roof + 0.08
		_box(root, Vector3(1.2, 0.1, 0.3), Vector3(0, bar_y, (s.ws1 + s.re) * 0.5 + 0.3), dark)
		var red := StandardMaterial3D.new(); red.albedo_color = Color(0.3, 0, 0); red.emission_enabled = true; red.emission = Color(1, 0.05, 0.05); red.emission_energy_multiplier = 0.2
		var blue := StandardMaterial3D.new(); blue.albedo_color = Color(0, 0, 0.3); blue.emission_enabled = true; blue.emission = Color(0.1, 0.3, 1); blue.emission_energy_multiplier = 0.2
		_box(root, Vector3(0.52, 0.13, 0.27), Vector3(-0.3, bar_y + 0.08, (s.ws1 + s.re) * 0.5 + 0.3), red)
		_box(root, Vector3(0.52, 0.13, 0.27), Vector3(0.3, bar_y + 0.08, (s.ws1 + s.re) * 0.5 + 0.3), blue)
		fl = {"red": red, "blue": blue}
	if kind == "cashvan":
		for sd in [-1.0, 1.0]:
			var t := Label3D.new()
			t.text = "مصرف الشرق · نقل أموال"
			t.font = load("res://assets/fonts/Tajawal-Bold.ttf")
			t.font_size = 64; t.pixel_size = 0.006; t.outline_size = 0
			t.modulate = Color(0.95, 0.85, 0.5)
			t.position = Vector3(sd * (W * 0.5 + 0.03), s.belt + 0.25, -0.3)
			t.rotation.y = sd * PI / 2
			root.add_child(t)
	if kind == "swat":
		for i in 5:
			_box(root, Vector3(0.06, 0.5, 0.06), Vector3(-0.6 + i * 0.3, base + 0.35, hl + 0.2), dark)
		_box(root, Vector3(W * 0.9, 0.08, 0.08), Vector3(0, base + 0.62, hl + 0.2), dark)
	root.set_meta("flashers", fl)
	root.set_meta("spec", s)
	if with_wheels:
		for wzp in [wz, -wz]:
			for sd in [-1.0, 1.0]:
				var wh := wheel(root, r, 0.24 if base_kind == "sedan" else 0.3)
				wh.position = Vector3(sd * (W * 0.5 - 0.12), r, wzp)
	return root

## Collapse a built car into one MeshInstance (one surface per material) + its text labels.
static func compact(node: Node3D) -> Node3D:
	# rigged parts (e.g. the SWAT truck's rear doors) need their skeleton: keep such models as they are
	for sk in node.find_children("*", "MeshInstance3D", true, false):
		if sk.skin and sk.visible:
			return node
	var groups := {}
	var labels := []
	var stack := [[node, Transform3D.IDENTITY]]
	while stack.size():
		var it: Array = stack.pop_back()
		var n: Node3D = it[0]
		var xf: Transform3D = it[1]
		for ch in n.get_children():
			if ch is Node3D:
				var cxf: Transform3D = xf * ch.transform
				if ch is MeshInstance3D and ch.mesh and ch.visible:
					for si in ch.mesh.get_surface_count():
						var m: Material = ch.material_override
						if not m:
							m = ch.get_surface_override_material(si)
						if not m:
							m = ch.mesh.surface_get_material(si)
						if not groups.has(m):
							var s := SurfaceTool.new(); s.begin(Mesh.PRIMITIVE_TRIANGLES)
							groups[m] = s
						groups[m].append_from(ch.mesh, si, cxf)
				elif ch is Label3D:
					labels.append([ch, cxf])
				stack.append([ch, cxf])
	var am := ArrayMesh.new()
	for m in groups:
		groups[m].commit(am)
		am.surface_set_material(am.get_surface_count() - 1, m)
	var out := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = am
	out.add_child(mi)
	for l in labels:
		var lbl: Label3D = l[0]
		lbl.get_parent().remove_child(lbl)
		lbl.transform = l[1]
		out.add_child(lbl)
	for k in node.get_meta_list():
		out.set_meta(k, node.get_meta(k))
	node.free()
	return out
