---
template: home
variables:
  title: Blue Turtle Canada
---

Bonjour, bienvenue à {{ title }} !

Cette page a été construite avec **Calgary**, un générateur de sites statiques
dont le pipeline de build est du code Swift. L'en-tête et le pied de page sont
des composants — de simples fichiers HTML que le template inclut.

{% include "components/hero" title="{{ title }}" %}

## Comment cette page est construite

- `content/index.fr-fr.md` est la page que vous lisez.
- `templates/home.html` est le template dans lequel elle est rendue.
- `components/header.html` et `components/footer.html` sont inclus par le template.
- `components/hero.html` est un composant que la page inclut.

## Derniers articles

Les articles ci-dessous viennent de la collection `blog` — la même liste que
celle que l'index du blog rend :

{% for post in site.blog %}
- [{{ post.title }}]({{ post.url }}) — {{ post.description }}
{% endfor %}
