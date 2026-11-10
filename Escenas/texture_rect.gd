extends TextureRect

func _ready() -> void:
	get_viewport().size_changed.connect(_fit)
	_fit()

func _fit() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size
