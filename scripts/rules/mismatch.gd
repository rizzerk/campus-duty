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


## A difference that matters: not one of the student's harmless short forms.
static func real_differs(student: Dictionary, form: Dictionary, key: String) -> bool:
	return differs(student, form, key) and not student.get("harmless", []).has(key)


## Every paper field that really disagrees with the record, as [form_index, key] pairs.
static func real_differences(student: Dictionary) -> Array:
	var found: Array = []
	for i in student["papers"].size():
		var form: Dictionary = student["papers"][i]
		for key: String in form["fields"]:
			if real_differs(student, form, key):
				found.append([i, key])
	return found


## Is one of the player's flags right? Flags are {form, key, context}; for a signature the
## context is the adviser whose specimen they compared against, and it must be the one on the slip.
static func flag_is_real(student: Dictionary, flag: Dictionary) -> bool:
	var form: Dictionary = student["papers"][flag["form"]]
	if flag["key"] == "signature" and flag.get("context", "") != form["fields"].get("adviser", ""):
		return false
	return real_differs(student, form, flag["key"])


static func score_flags(student: Dictionary, flags: Array) -> Dictionary:
	var caught := 0
	var false_alarms := 0
	for flag: Dictionary in flags:
		if flag_is_real(student, flag):
			caught += 1
		else:
			false_alarms += 1
	return { "caught": caught, "false_alarms": false_alarms }
