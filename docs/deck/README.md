# Slide deck

The product presentation, in Spanish: what DeadDrop is, who it is for, and
how the protocol works. Seventeen slides, 1920x1080.

```sh
./docs/deck/build.sh            # → docs/deck/deaddrop-deck.pdf
./docs/deck/build.sh out.pdf    # → somewhere else
```

Each slide is one `<section>` in `slides/`, ordered by `deck.json`. An
`<aside>` holds speaker notes and never renders.

## Two things that bite

**Boxes need `box-sizing:border-box`.** Several slides position boxes
absolutely and give them a `height`. Without `box-sizing` the padding is
added on top, so a box declared 104px tall measures 150 — rows that were
drawn 60px apart end up touching, and connector arrows drawn from the
declared coordinates land inside the boxes instead of between them.

**Prefer `min-height` to `height`.** A box whose text needs more room than
its declared height spills over whatever is below it. `min-height` keeps
the intended size as a floor and lets the box grow.

Both were real bugs here. A footer positioned at `bottom:64px` is the same
trap from the other direction: it does not participate in layout, so it
sits on top of whatever reaches that far down. Footers are ordinary flow
children now.

## Checking a change

Render a slide at exactly 1920x1080 and look for anything crossing the
bottom edge or overlapping a neighbour — measuring beats eyeballing, since
a 13px overlap is invisible in a thumbnail and obvious on a projector.
