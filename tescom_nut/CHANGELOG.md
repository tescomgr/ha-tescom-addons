# Changelog

## 2.8.4-2

- Tescom Leo SmartBox, Leo LCD and Neoline work with no settings: the add-on
  adds the settings their USB chip needs, tells the model from the reading
  and restarts the UPS once with that model's settings and name (Tescom,
  "Leo SmartBox", "Leo LCD", "Neoline"). The model is remembered.
- Tescom LiON and Prime: their full settings from Tescom's profiles.
- `config` lines: a setting given there replaces the add-on's own; values
  with spaces or quotes are quoted (a model name was cut at the space).
- The documentation says what to do when Home Assistant shows no NUT card,
  how to enable the sensors it creates disabled, and that the Leo's battery
  charge is estimated from its voltage.

## 2.8.4-1

- First version: NUT 2.8.4, with `nutdrv_qx_mec` (Tescom LiON RT) and the
  quick battery test in `nutdrv_qx` (Tescom Leo SmartBox).
- Tescom Prime: activated with its myTescom activation code, which fetches
  its driver from Tescom Connect.
- USB detection, and discovery for Home Assistant's Network UPS Tools
  integration.
