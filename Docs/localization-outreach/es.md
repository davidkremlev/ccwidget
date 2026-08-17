<!--
Ready to post as an issue once the repository exists. Title and body are in
Spanish on purpose: someone who reads Spanish should not have to read an
English request first. Label it "help wanted" and pin it.
-->

**Título:** Traducción al español: se busca revisión de hablantes nativos

---

`ccwidget` es un widget pequeño para el escritorio de macOS. Muestra cuánto has
consumido de tu suscripción de Claude, cuán llena está la ventana de contexto y
cuándo se agotará previsiblemente la cuota semanal.

La interfaz está en seis idiomas. El inglés y el ruso son de hablantes nativos;
el español no — lo traduje yo lo mejor que supe. **Una lectura de alguien que lo
tenga como lengua materna valdría muchísimo.**

No hace falta retraducir nada. Busco las dos cosas que un diccionario no
detecta: frases correctas que nadie dice, y un registro que no encaja. Un
ejemplo que ya salió: la etiqueta de una fila decía `Semana usada`, que suena a
"una semana que fue usada" y no a "cuánto llevas consumido de la semana". Ahora
dice `Consumo semanal`. Seguro que quedan más.

Las 112 cadenas están en
[`Docs/localization-review.md`](https://github.com/davidkremlev/ccwidget/blob/main/Docs/localization-review.md), junto con el
contexto que condiciona la redacción: por ejemplo, que las tres barras crecen
en la misma dirección, y que en una tarjeta de 338 puntos de ancho el texto se
corta a partir de unos 22 caracteres.

**Una línea en este issue es suficiente:**

```
"Week used" (es) → "Consumo semanal" quedaría mejor como …
```

No hace falta pull request ni saber Swift. Si prefieres editar directamente,
las cadenas son JSON en `App/Resources/Localizable.xcstrings` y
`Widget/Resources/Localizable.xcstrings`.

Gracias de antemano, aunque sea por una sola corrección. Una línea que suene
natural vale más que una traducción completa pero acartonada.
