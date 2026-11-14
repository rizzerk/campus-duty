class_name Money
extends RefCounted
## Peso amounts. Papers and ISMIS show them as text ("PHP 18,450.00"); rules and tools work in
## whole pesos. Pure, so the generator, the rules and the tests share one way of writing money.


## 18450 -> "PHP 18,450.00".
static func format(pesos: int) -> String:
	var digits := str(absi(pesos))
	var grouped := ""
	while digits.length() > 3:
		grouped = "," + digits.right(3) + grouped
		digits = digits.left(digits.length() - 3)
	return "%sPHP %s%s.00" % ["-" if pesos < 0 else "", digits, grouped]


## "PHP 18,450.00" -> 18450. Centavos and any minus sign are dropped (amounts on papers are never
## negative); anything without digits reads as 0.
static func parse(text: String) -> int:
	var whole := text.get_slice(".", 0)
	var digits := ""
	for character in whole:
		if character >= "0" and character <= "9":
			digits += character
	return int(digits) if digits != "" else 0
