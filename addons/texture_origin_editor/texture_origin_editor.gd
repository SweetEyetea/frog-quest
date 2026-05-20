@tool
extends EditorPlugin

const PluginName = "TextureOriginEditor"

var dock
var tileset_selector
var reload_button
var tile_grid
var selected_tiles = []
var current_tileset = null
var anchor_buttons = []
var tile_preview_size = 64

func _enter_tree():
	dock = _create_editor_dock()
	add_control_to_dock(DOCK_SLOT_RIGHT_BL, dock)
	
	tileset_selector.item_selected.connect(_on_tileset_selected)
	
	reload_button.pressed.connect(_on_reload_button_pressed)

func _exit_tree():
	remove_control_from_docks(dock)
	dock.free()

func _create_editor_dock():
	var main_container = VBoxContainer.new()
	main_container.name = "TextureOriginEditor"
	
	var tileset_container = HBoxContainer.new()
	var tileset_label = Label.new()
	tileset_label.text = "Tileset: "
	tileset_selector = OptionButton.new()
	tileset_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	reload_button = Button.new()
	reload_button.text = "Reload"
	reload_button.tooltip_text = "Updates the list of tilesets and tiles"
	
	tileset_container.add_child(tileset_label)
	tileset_container.add_child(tileset_selector)
	tileset_container.add_child(reload_button)
	main_container.add_child(tileset_container)
	
	var size_container = HBoxContainer.new()
	var size_label = Label.new()
	size_label.text = "Preview Size: "
	size_container.add_child(size_label)
	
	var size_slider = HSlider.new()
	size_slider.min_value = 32
	size_slider.max_value = 128
	size_slider.step = 8
	size_slider.value = tile_preview_size
	size_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_slider.connect("value_changed", _on_size_slider_changed)
	size_container.add_child(size_slider)
	
	main_container.add_child(size_container)
	
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	tile_grid = GridContainer.new()
	tile_grid.columns = 4
	
	var grid_container = VBoxContainer.new()
	grid_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	grid_container.add_child(tile_grid)
	scroll.add_child(grid_container)
	main_container.add_child(scroll)
	
	dock = main_container
	dock.resized.connect(_on_dock_resized)
	
	var anchor_container = VBoxContainer.new()
	var anchor_label = Label.new()
	anchor_label.text = "Set Origin:"
	anchor_container.add_child(anchor_label)
	
	var anchor_grid = GridContainer.new()
	anchor_grid.columns = 3
	
	var anchor_positions = [
		"Top Left", "Top Center", "Top Right",
		"Middle Left", "Middle Center", "Middle Right",
		"Bottom Left", "Bottom Center", "Bottom Right"
	]
	
	for i in range(9):
		var button = Button.new()
		button.text = anchor_positions[i]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.connect("pressed", _on_anchor_button_pressed.bind(i))
		anchor_grid.add_child(button)
		anchor_buttons.append(button)
	
	anchor_container.add_child(anchor_grid)
	main_container.add_child(anchor_container)
	
	var selection_buttons_container = HBoxContainer.new()
	selection_buttons_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var select_all_button = Button.new()
	select_all_button.text = "Select All"
	select_all_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	select_all_button.connect("pressed", _select_all_tiles)
	selection_buttons_container.add_child(select_all_button)
	
	var clear_button = Button.new()
	clear_button.text = "Clear Selection"
	clear_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clear_button.connect("pressed", _clear_selection)
	selection_buttons_container.add_child(clear_button)
	
	main_container.add_child(selection_buttons_container)
	
	_update_tileset_list()
	
	return main_container

func _on_size_slider_changed(value):
	tile_preview_size = value
	if dock.has_node("SizeValueLabel"):
		dock.get_node("SizeValueLabel").text = str(value)
	_update_tile_grid()
	_update_columns_count()

func _on_reload_button_pressed():
	print("Update Tiletets and Tiles...")
	
	var current_selection = ""
	if tileset_selector.selected >= 0:
		current_selection = tileset_selector.get_item_text(tileset_selector.selected)
	
	_update_tileset_list()
	
	if current_selection != "":
		for i in range(tileset_selector.item_count):
			if tileset_selector.get_item_text(i) == current_selection:
				tileset_selector.select(i)
				_on_tileset_selected(i)
				return
	
	if tileset_selector.item_count > 0:
		tileset_selector.select(0)
		_on_tileset_selected(0)

func _update_tileset_list():
	tileset_selector.clear()
	
	var dir = DirAccess.open("res://")
	if dir:
		_scan_for_tilesets(dir, "res://")
	
	if tileset_selector.item_count > 0:
		tileset_selector.select(0)
		_on_tileset_selected(0)

func _scan_for_tilesets(dir, path):
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		if dir.current_is_dir() and file_name != "." and file_name != "..":
			var subdir = DirAccess.open(path + file_name + "/")
			if subdir:
				_scan_for_tilesets(subdir, path + file_name + "/")
		elif file_name.ends_with(".tres") or file_name.ends_with(".res"):
			var res_path = path + file_name
			var res = load(res_path)
			if res is TileSet:
				tileset_selector.add_item(res_path)
				
		file_name = dir.get_next()
	
	dir.list_dir_end()

func _on_tileset_selected(index):
	var tileset_path = tileset_selector.get_item_text(index)
	current_tileset = load(tileset_path)
	_update_tile_grid()
	_update_columns_count()

func _update_tile_grid():
	for child in tile_grid.get_children():
		tile_grid.remove_child(child)
		child.queue_free()
	
	selected_tiles.clear()
	
	if current_tileset == null:
		return
	
	var source_count = current_tileset.get_source_count()
	var handled_sources_count = 0
	var current_id = 0

	while handled_sources_count < source_count:
		if current_tileset.has_source(current_id):
			var source = current_tileset.get_source(current_id)

			if source is TileSetAtlasSource:
				var source_size = source.get_atlas_grid_size()
				
				for y in range(source_size.y):
					for x in range(source_size.x):
						var tile_pos = Vector2i(x, y)
						if source.has_tile(tile_pos):
							var tile_button = _create_tile_button(source, current_id, tile_pos)
							if tile_button != null:
								tile_grid.add_child(tile_button)
				handled_sources_count += 1
				current_id += 1
		else:
			current_id += 1

func _create_tile_button(source, source_id, tile_pos):
	var container = Control.new()
	container.custom_minimum_size = Vector2(tile_preview_size, tile_preview_size)
	
	var button = TextureButton.new()
	var texture_region = source.get_tile_texture_region(tile_pos)
	
	var atlas_texture = AtlasTexture.new()
	atlas_texture.atlas = source.texture
	atlas_texture.region = texture_region
	atlas_texture.filter_clip = true
	
	button.texture_normal = atlas_texture
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	
	button.custom_minimum_size = Vector2(tile_preview_size, tile_preview_size)
	button.size = Vector2(tile_preview_size, tile_preview_size)
	button.position = Vector2.ZERO
	
	button.tooltip_text = "Position: " + str(tile_pos)
	
	button.set_meta("source_id", source_id)
	button.set_meta("tile_pos", tile_pos)
	
	button.pressed.connect(func(): _on_tile_selected(container))
	
	var origin_indicator = ColorRect.new()
	origin_indicator.size = Vector2(6, 6)
	origin_indicator.color = Color(1, 0, 0, 0.7)
	
	var tile_data = source.get_tile_data(tile_pos, 0)
	var origin = Vector2.ZERO
	
	if tile_data:
		origin = Vector2(tile_data.texture_origin)
	
	var origin_pos = _calculate_origin_indicator_position(texture_region.size, origin)
	
	origin_indicator.position = origin_pos - Vector2(3, 3)
	
	container.add_child(button)
	container.add_child(origin_indicator)
	
	container.set_meta("source_id", source_id)
	container.set_meta("tile_pos", tile_pos)
	container.set_meta("button", button)
	container.set_meta("origin_indicator", origin_indicator)
	
	return container

func _calculate_origin_indicator_position(texture_size, origin):

	if texture_size.x <= 0 or texture_size.y <= 0:
		return Vector2(tile_preview_size / 2, tile_preview_size / 2)
	
	var scale_factor = min(
		float(tile_preview_size) / float(texture_size.x), 
		float(tile_preview_size) / float(texture_size.y)
	)
	
	var container_center = Vector2(tile_preview_size / 2, tile_preview_size / 2)
	
	# Berechne die skalierte Größe der Textur
	var scaled_size = Vector2(texture_size) * scale_factor
	
	var final_pos = container_center + (origin * scale_factor)
	
	return final_pos

func _on_tile_selected(container):
	var is_already_selected = selected_tiles.has(container)
	var button = container.get_meta("button")
	
	var is_multi_select = Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META)
	
	if is_multi_select:
		if is_already_selected:
			selected_tiles.erase(container)
			button.modulate = Color(1, 1, 1, 1)
		else:
			selected_tiles.append(container)
			button.modulate = Color(0.5, 0.8, 1, 1)
	else:
		_clear_selection()
		selected_tiles.append(container)
		button.modulate = Color(0.5, 0.8, 1, 1)

func _select_all_tiles():
	_clear_selection()
	
	for container in tile_grid.get_children():
		if container.has_meta("button"):
			selected_tiles.append(container)
			var button = container.get_meta("button")
			button.modulate = Color(0.5, 0.8, 1, 1)
	
	print("All Tiles selected: ", selected_tiles.size(), " Tiles")

func _clear_selection():
	for container in selected_tiles:
		var button = container.get_meta("button")
		button.modulate = Color(1, 1, 1, 1)
	selected_tiles.clear()

func _on_anchor_button_pressed(anchor_index):
	if selected_tiles.size() == 0 or current_tileset == null:
		return
	
	var column = anchor_index % 3
	var row = anchor_index / 3
	
	for container in selected_tiles:
		var source_id = container.get_meta("source_id")
		var tile_pos = container.get_meta("tile_pos")
		var source = current_tileset.get_source(source_id)
		
		if source is TileSetAtlasSource:
			var texture_region = source.get_tile_texture_region(tile_pos)
			var tile_size = texture_region.size
			
			var origin = Vector2()
			
			match column:
				0: origin.x = -tile_size.x / 2
				1: origin.x = 0
				2: origin.x = tile_size.x / 2
			
			match row:
				0: origin.y = -tile_size.y / 2
				1: origin.y = 0
				2: origin.y = tile_size.y / 2
			
			origin.x += -sign(origin.x) * abs(current_tileset.tile_size.x / 2)
			origin.y += -sign(origin.y) * abs(current_tileset.tile_size.y / 2)

			var tile_data = source.get_tile_data(tile_pos, 0)
			if tile_data:
				tile_data.texture_origin = origin
				
				if container.has_meta("origin_indicator"):
					var origin_indicator = container.get_meta("origin_indicator")
					var new_pos = _calculate_origin_indicator_position(texture_region.size, origin)
					origin_indicator.position = new_pos - Vector2(3, 3)

func _on_dock_resized():
	_update_columns_count()

func _update_columns_count():
	if tile_grid == null:
		return
		
	var dock_width = dock.size.x
	var tile_width = tile_preview_size + 6
	
	var columns = max(2, int(dock_width / tile_width))
	
	if tile_grid.columns != columns:
		tile_grid.columns = columns

func _handles(object):
	return false