class_name Mismatch
extends RefCounted
## Papers and the ISMIS record share field keys, so a flag is just "this field on the paper
## differs from the same field on the record".


static func record_value(student: Dictionary, form: Dictionary, key: String) -> Variant:
	if key == "signature":
		for adviser: Dictionary in student["record"]["advisers"]:
			if adviser["name"] == form["fields"].get("adviser", ""):
				return adviser["specimen"]
		return null
	return student["record"].get(key, null)


static func comparable(student: Dictionary, form: Dictionary, key: String) -> bool:
	return form["fields"].has(key) and record_value(student, form, key) != null


static func differs(student: Dictionary, form: Dictionary, key: String) -> bool:
	if not comparable(student, form, key):
		return false
	return str(form["fields"][key]) != str(record_value(student, form, key))


## Every paper field that disagrees with the record, as [form_index, key] pairs.
static func all_differences(student: Dictionary) -> Array:
	var found: Array = []
	for i in student["papers"].size():
		var form: Dictionary = student["papers"][i]
		for key: String in form["fields"]:
			if differs(student, form, key):
				found.append([i, key])
	return found
