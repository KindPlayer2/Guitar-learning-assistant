extends OptionButton

@export var intro_page: Button
@export var c_page: Button
@export var g_page: Button
@export var d_page: Button
@export var a_page: Button
@export var am_page: Button
@export var b_page: Button
@export var bm_page: Button
@export var dm_page: Button
@export var d7_page: Button
@export var e_page: Button
@export var em_page: Button
@export var f_page: Button
@export var g7_page: Button


func _ready():
	# Connect the item_selected signal to our function
	item_selected.connect(_on_option_selected)
	# Set initial state (show intro, hide others)
	_on_option_selected(0)

func _on_option_selected(index: int):
	# Hide all pages first
	intro_page.visible = false
	c_page.visible = false
	g_page.visible = false
	d_page.visible = false
	a_page.visible = false
	am_page.visible = false
	b_page.visible = false
	bm_page.visible = false
	dm_page.visible = false
	d7_page.visible = false
	e_page.visible = false
	em_page.visible = false
	f_page.visible = false
	g7_page.visible = false

	
	# Show the selected page based on index
	match index:
		0:
			intro_page.visible = true
		1:
			a_page.visible = true
		2:
			am_page.visible = true
		3:
			b_page.visible = true
		4:
			bm_page.visible = true
		5:
			c_page.visible = true
		6:
			d_page.visible = true
		7:
			dm_page.visible = true
		8:
			d7_page.visible = true
		9:
			e_page.visible = true
		10:
			em_page.visible = true
		11:
			f_page.visible = true
		12:
			g_page.visible = true
		13:
			g7_page.visible = true
