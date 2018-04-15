## Basic prettify tests

### Prettify without arguments

<?code-excerpt "quote.md">
{% prettify %}
This is a **markdown** fragment.
{% endprettify %}

### Prettify with arguments

<?code-excerpt "basic.dart (greeting)">
{% prettify dart %}
var greeting = 'hello';
var scope = 'world';
{% endprettify %}

<?code-excerpt "no_region.html">
{% prettify html %}
<div>
  <h1>Hello World!</h1>
</div>
{% endprettify %}

<?code-excerpt "no_region.html">
{% prettify html tag="code" %}
<div>
  <h1>Hello World!</h1>
</div>
{% endprettify %}
