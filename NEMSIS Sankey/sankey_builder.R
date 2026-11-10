# =============================================================================
# sankey_builder.R
# Draws an interactive Sankey from a composite path table with
# networkD3::sankeyNetwork().
#
# Above the diagram, each variable has a tick box and a row of its levels:
#   - unticking a variable removes its column; the flows either side join up
#   - unticking a level leaves that level's records out (for example, keeping
#     only Rural and Wilderness, or only Cardiac)
# The diagram is redrawn in the browser from the path table each time, so no
# R session or server is needed once the page has been made.
#
# How to read the result:
#   - the width of a flow is its number of records
#   - the colour of a flow is the level it started from in the first column
#   - each level of the first column runs across the diagram in a lane of its
#     own (see sankey_keep_lanes below)
#   - hovering over a node follows the records that pass through it: the share
#     of every flow that they make up is drawn over the faded diagram. Clicking
#     the node keeps the trace until the node is clicked again
#   - two tick boxes above the diagram switch the lanes on and off, and switch
#     between numbers of records and percents of each lane
#   - each column has a title, and each node label carries its share of the
#     records drawn
# A chooser sets which variable is the first column; its colours then run
# through the whole diagram.
#
# Needs tidyverse loaded, plus the networkD3, htmlwidgets, htmltools and
# jsonlite packages installed.
# =============================================================================

# ---- Look and feel (edit to restyle every Sankey) ------------------------------

# One typeface for the page and the figure: the font of the reader's own system,
# which is also what the site's pages use. Nothing is fetched from another site.
sankey_font        <- "-apple-system, BlinkMacSystemFont, Segoe UI, Helvetica Neue, Arial, sans-serif"
sankey_background  <- "#ffffff"   # the figure sits straight on a white page, with no card around it
sankey_muted       <- "#6f6a64"   # the one secondary text colour: subtitle, filter summary, note (5.4 to 1 on white)
sankey_node_colour <- "#1B3A5C"   # medical navy: column titles and control labels, and nodes when sankey_node_colours is "navy"

# Node colours after the first column:
#   "own"   each node takes the colour of its own level (a Cardiac node is red,
#           a Ground ALS node is blue), as given in the list of variables
#   "navy"  every node after the first column is navy
sankey_node_colours <- "navy"
sankey_band_opacity <- 0.70       # how solid the flows are: 1 is fully solid, 0.5 is half see-through

# Lanes. When TRUE, each level of the first column keeps its own set of nodes in
# every later column, so its records run across the diagram without merging
# with those of another level. When FALSE, each level has one shared node per column.
# This sets how the page opens; a tick box on the page switches between the two.
sankey_keep_lanes       <- TRUE

# Percents. When TRUE (and lanes are kept), every lane is drawn to the same
# height, so the width of a band is its percent of the lane and not its number
# of records; lanes of very different sizes can then be compared side by side.
# This sets how the page opens; a tick box on the page switches it.
sankey_lane_percent     <- FALSE
sankey_lane_padding     <- 7      # gap between nodes, in pixels, when lanes are kept
sankey_min_label_height <- 13     # with lanes kept, a node shorter than this many pixels has no label

# Text in the diagram, in pixels. Node labels take this size; the percent after
# a label and the column titles are a little smaller. The text of the controls
# and the note is set in sankey_css below.
sankey_label_size <- 15

# Width. The diagram fills the width of the page, less a right margin that is
# sized to the longest label of the last column plus this many pixels (room for
# the gap and the percent that follows the name).
sankey_label_room <- 84

# Shading inside a lane. Every flow in a lane has the colour of its first-column
# level; the shade of that colour can carry a second piece of information:
#   "second"    the level of the second column, kept all the way across, so that
#               each pairing of the first two columns can be followed to the end
#   "previous"  the level the flow has just left, in the column to its left
#   "none"      one shade for the whole lane
sankey_lane_shading <- "none"

# Used for a level that is not given a colour.
sankey_fallback_colours <- c("#7fa8c9", "#e0a458", "#2e8b6f", "#7b3f99", "#c0504d", "#5b6c8f")

# ---- Styles for the title, the controls and the note --------------------------------
# FONT, NAVY and MUTED are filled in from the settings above when the page is made.
# The controls are native tick boxes and plain choosers, set straight on the page.

sankey_css <- "
.sankey-head { font-family: FONT; color: #2a2520; padding: 0 0 12px; }
.sankey-head h3 { font-size: 23px; font-weight: 700; color: #1a1a1a; letter-spacing: -0.3px; margin: 0 0 2px; padding: 0; border: 0; }
.sankey-head .sankey-subtitle { font-size: 16.5px; color: MUTED; margin: 0 0 16px; }
.sankey-controls { font-size: 16.5px; line-height: 1.5; }
.sankey-controls label { cursor: pointer; margin: 0; white-space: nowrap; }
.sankey-controls label.off { color: MUTED; }
.sankey-controls input[type=checkbox] { width: 16px; height: 16px; margin: 0 8px 0 0; vertical-align: -2px; accent-color: NAVY; cursor: pointer; }
.sankey-controls input[type=checkbox]:disabled { cursor: default; }
.sankey-controls select { font: inherit; color: #2a2520; background: transparent; border: 0; border-bottom: 1px solid MUTED; border-radius: 0; padding: 0 2px; margin: 0 0 0 4px; cursor: pointer; }
.sankey-layout { display: flex; flex-wrap: wrap; align-items: baseline; gap: 8px 34px; }
.sankey-options { display: inline-flex; flex-wrap: wrap; align-items: baseline; gap: 8px 34px; }
.sankey-key { display: inline-flex; flex-wrap: wrap; align-items: baseline; gap: 4px 16px; margin-left: -18px; }
.sankey-swatch { display: inline-block; width: 13px; height: 13px; margin-right: 7px; }
.sankey-reset { font: inherit; color: MUTED; background: none; border: 0; padding: 0; margin-left: auto; text-decoration: underline; cursor: pointer; }
.sankey-variables { display: flex; flex-wrap: wrap; gap: 14px 44px; border-top: 1px solid #e4e0da; margin-top: 12px; padding-top: 12px; }
.sankey-variable-name { display: flex; align-items: center; font-size: 22px; font-weight: 600; color: NAVY; line-height: 1.3; }
.sankey-variable.off .sankey-variable-name, .sankey-variable.off summary { color: #8a8580; }
.sankey-controls input.sankey-switch { appearance: none; -webkit-appearance: none; flex: none; position: relative; width: 34px; height: 18px; margin: 0 10px 0 0; border-radius: 2px; background: #b8b3ad; cursor: pointer; }
.sankey-controls input.sankey-switch::after { content: ''; position: absolute; top: 2px; left: 2px; width: 14px; height: 14px; background: #ffffff; transition: left 0.12s; }
.sankey-controls input.sankey-switch:checked { background: NAVY; }
.sankey-controls input.sankey-switch:checked::after { left: 18px; }
.sankey-controls input.sankey-switch:focus-visible { outline: 2px solid NAVY; outline-offset: 2px; }
@media (prefers-reduced-motion: reduce) { .sankey-controls input.sankey-switch::after { transition: none; } }
.sankey-levels { position: relative; margin: 3px 0 0 44px; }
.sankey-levels summary { cursor: pointer; color: MUTED; width: fit-content; }
.sankey-levels fieldset { position: absolute; top: 100%; left: 0; z-index: 30; min-width: max-content; max-width: 320px; margin: 4px 0 0; padding: 8px 16px 8px 10px; background: #ffffff; border: 1px solid #cfcac3; }
.sankey-levels fieldset label { display: block; white-space: normal; padding: 2px 0 2px 24px; text-indent: -24px; }
.sankey-legend { font-size: 16.5px; font-weight: 600; color: NAVY; }
.sankey-legend:not(:empty) { margin-top: 10px; }
.sankey-note { font-family: FONT; font-size: 14px; line-height: 1.5; color: MUTED; margin: 0; padding: 10px 0 0; }
"

# ---- Controls, redrawing, labels and tooltip, run in the browser -------------------

sankey_explorer_js <- '
function(el, x, data) {
  var instance = (this && this.sankey) ? this : el.htmlwidget_data_init_result;
  var binding  = (window.HTMLWidgets.widgets || []).filter(function(w) {
    return w.name === "sankeyNetwork";
  })[0];

  // The header and note are made by R next to the diagram; they are looked for
  // in the enclosing elements, nearest first.
  function findNear(selector) {
    var node = el.parentNode;
    while (node && node.querySelector) {
      var hit = node.querySelector(selector);
      if (hit) return hit;
      node = node.parentNode;
    }
    return null;
  }

  var panel   = findNear(".sankey-controls");
  var legend  = findNear(".sankey-legend");
  var noteEl  = findNear(".sankey-note");
  var navy    = data.node_colour;
  var base    = data.band_opacity;
  var count   = d3.format(",");
  var stages  = data.stages;

  d3.select(el).style("background", data.background);

  // ---- The path table, one object per row --------------------------------------
  var rows = [];
  for (var i = 0; i < data.paths.n.length; i++) {
    var row = { n: +data.paths.n[i] };
    stages.forEach(function(s) { row[s.key] = data.paths[s.key][i]; });
    rows.push(row);
  }

  // Every level starts switched on.
  stages.forEach(function(s) { s.selected = s.levels.slice(); });

  // The variable chosen as the first column. Its levels give the flows their
  // colours all the way across the diagram.
  var firstKey = stages.filter(function(s) { return s.on; })[0].key;

  // The displayed variables, with the chosen one moved to the front and the
  // rest left in their usual order.
  function displayed() {
    var on = stages.filter(function(s) { return s.on; });
    var first = on.filter(function(s) { return s.key === firstKey; })[0] || on[0];
    firstKey = first.key;
    return [first].concat(on.filter(function(s) { return s !== first; }));
  }

  // For each flow group, the second-column level it carries (when that sets the shade).
  var viaOf = {};

  // Whether each first-column level keeps a lane of its own, and whether every
  // lane is drawn to the same height (percents of the lane). Both can be
  // switched from the controls.
  var split   = data.keep_lanes;
  var percent = split && data.lane_percent;

  // Paths running through a flow smaller than this percent are not drawn. The
  // percent is of the records shown or, with lanes drawn as percents, of the
  // lane. It can be changed from the controls.
  var minPct = +data.min_link_pct;

  // ---- Tooltip, made once --------------------------------------------------------
  var tip = d3.select("body").append("div")
    .style("position", "absolute")
    .style("background", "rgba(26,26,26,0.92)")
    .style("color", "#fff")
    .style("padding", "8px 12px")
    .style("border-radius", "6px")
    .style("font-family", data.font)
    .style("font-size", "14px")
    .style("pointer-events", "none")
    .style("opacity", 0)
    .style("box-shadow", "0 4px 12px rgba(0,0,0,0.2)")
    .style("z-index", 1000);

  function show(html) { tip.html(html).transition().duration(150).style("opacity", 1); }
  function move() {
    tip.style("left", (d3.event.pageX + 14) + "px").style("top", (d3.event.pageY - 20) + "px");
  }
  function hide() { tip.transition().duration(200).style("opacity", 0); }

  // ---- Work out what to draw from the current choices -------------------------------
  function compute() {
    var visible = displayed();

    // A record is used when it passes every level choice. In a displayed
    // variable it must also have a recorded value; in a hidden variable with
    // nothing switched off, any value passes.
    var combos = {};
    rows.forEach(function(r) {
      for (var j = 0; j < stages.length; j++) {
        var s = stages[j];
        var nothingOff = s.selected.length === s.levels.length;
        if ((s.on || !nothingOff) && s.selected.indexOf(r[s.key]) < 0) return;
      }
      var levels = visible.map(function(s) { return r[s.key]; });
      var id = levels.join("||");
      if (!combos[id]) combos[id] = { levels: levels, n: 0 };
      combos[id].n += r.n;
    });

    var paths = Object.keys(combos).map(function(id) { return combos[id]; });
    var shown = d3.sum(paths, function(p) { return p.n; });

    // Flows between neighbouring columns, kept apart by first-column level, and
    // by second-column level as well when that level sets the shade.
    var carry = split && data.lane_shading === "second";
    function flowId(p, k) {
      return k + "||" + p.levels[k] + "||" + p.levels[k + 1] + "||" + p.levels[0] + "||" + (carry ? p.levels[1] : "");
    }
    function flowsOf(list) {
      var f = {};
      list.forEach(function(p) {
        for (var k = 0; k < visible.length - 1; k++) {
          f[flowId(p, k)] = (f[flowId(p, k)] || 0) + p.n;
        }
      });
      return f;
    }

    // Whole paths are dropped when any flow they run through is below the
    // cutoff, so that no node is left with nothing leaving it. Dropping paths
    // makes the remaining flows smaller, so this is repeated until every flow
    // left is at or above the cutoff.
    // With lanes drawn as percents, the percent cutoff is taken within each lane.
    var laneShown = {};
    paths.forEach(function(p) { laneShown[p.levels[0]] = (laneShown[p.levels[0]] || 0) + p.n; });
    function cutoffFor(p) {
      return Math.max((percent ? laneShown[p.levels[0]] : shown) * minPct / 100, data.min_link_n);
    }
    var cutoff = Math.max(shown * minPct / 100, data.min_link_n);
    var kept = paths, dropped = true;
    while (dropped) {
      var current = flowsOf(kept);
      var next = kept.filter(function(p) {
        for (var k = 0; k < visible.length - 1; k++) {
          if (current[flowId(p, k)] < cutoffFor(p)) return false;
        }
        return true;
      });
      dropped = next.length < kept.length;
      kept = next;
    }

    // Records drawn in each lane: the base for percents of a lane.
    var laneDrawn = {};
    kept.forEach(function(p) { laneDrawn[p.levels[0]] = (laneDrawn[p.levels[0]] || 0) + p.n; });

    return { visible: visible, kept: kept, flows: flowsOf(kept), flowsOf: flowsOf, shown: shown,
             drawn: d3.sum(kept, function(p) { return p.n; }), cutoff: cutoff, laneDrawn: laneDrawn };
  }

  // ---- Draw ------------------------------------------------------------------------
  function redraw() {
    var c = compute();
    var visible = c.visible, first = visible[0];

    writeLegend(c);
    writeNote(c);

    if (c.kept.length === 0) {
      d3.select(el).select("svg").selectAll("*").remove();
      return;
    }

    // Nodes, in column order and then in the level order of each variable.
    // With lanes kept, each first-column level has its own set of nodes in
    // every later column, so its records run across the diagram in one lane
    // and do not merge with those of another level.
    var nodeIndex = {}, names = [], groups = [], lanes = [];
    // The colour group of a node after the first column: its own level, or navy.
    function nodeGroup(k, li) { return data.node_colours === "own" ? "n" + k + "_" + li : "mid"; }
    visible.forEach(function(s, k) {
      if (k === 0 || !split) {
        s.levels.forEach(function(level, li) {
          if (!c.kept.some(function(p) { return p.levels[k] === level; })) return;
          nodeIndex[k + "||" + level] = names.length;
          names.push(level);
          groups.push(k === 0 ? "o" + li : nodeGroup(k, li));
          lanes.push(null);
        });
        return;
      }
      first.levels.forEach(function(origin) {
        s.levels.forEach(function(level, li) {
          if (!c.kept.some(function(p) { return p.levels[0] === origin && p.levels[k] === level; })) return;
          nodeIndex[k + "||" + origin + "||" + level] = names.length;
          names.push(level);
          groups.push(nodeGroup(k, li));
          lanes.push(origin);
        });
      });
    });
    function nodeAt(k, level, origin) {
      return nodeIndex[(k === 0 || !split) ? k + "||" + level : k + "||" + origin + "||" + level];
    }

    // Flows, in a fixed order so that the bands stack the same way each time.
    // The tone of a flow is the position of a level in its variable (0 is the
    // top level), out of the number of levels; it sets the shade within a lane.
    var list = Object.keys(c.flows).map(function(id) {
      var part = id.split("||"), k = +part[0], tone = null, via = null;
      if (split && data.lane_shading === "second") {
        tone = [visible[1].levels.indexOf(part[4]), visible[1].levels.length];
        via  = part[4];
      } else if (split && data.lane_shading === "previous" && k > 0) {
        tone = [visible[k].levels.indexOf(part[1]), visible[k].levels.length];
      }
      return { source: nodeAt(k, part[1], part[3]),
               target: nodeAt(k + 1, part[2], part[3]),
               origin: first.levels.indexOf(part[3]),
               tone: tone, via: via, id: id,
               n: c.flows[id],
               value: percent ? 1e6 * c.flows[id] / c.laneDrawn[part[3]] : c.flows[id] };
    });
    list.sort(function(a, b) {
      return (a.source - b.source) || (a.target - b.target) || (a.origin - b.origin) ||
             ((a.tone ? a.tone[0] : 0) - (b.tone ? b.tone[0] : 0));
    });

    // A lighter or darker shade of a lane colour: the top level is the lightest.
    function shade(base, tone) {
      if (!tone || tone[1] <= 1) return base;
      var colour = d3.hsl(base);
      colour.l = Math.max(0.22, Math.min(0.86, colour.l + 0.07 - 0.34 * tone[0] / (tone[1] - 1)));
      return colour.toString();
    }
    function groupOf(l) { return "l" + l.origin + (l.tone ? "_" + l.tone[0] + "_" + l.tone[1] : ""); }

    // Colours: first-column nodes and all flows take the colours of the first column.
    var domain = [], range = [];
    first.levels.forEach(function(level, li) {
      domain.push("o" + li, "l" + li);
      range.push(first.colours[li], first.colours[li]);
    });
    domain.push("mid");
    range.push(navy);
    if (data.node_colours === "own") {
      visible.forEach(function(s, k) {
        if (k === 0) return;
        s.levels.forEach(function(level, li) {
          domain.push(nodeGroup(k, li));
          range.push(s.colours[li]);
        });
      });
    }
    viaOf = {};
    list.forEach(function(l) {
      var group = groupOf(l);
      viaOf[group] = l.via;
      if (domain.indexOf(group) < 0) {
        domain.push(group);
        range.push(shade(first.colours[l.origin], l.tone));
      }
    });

    var options = {};
    for (var key in x.options) options[key] = x.options[key];
    options.colourScale = d3.scaleOrdinal().domain(domain).range(range);

    // The right margin is only as wide as the last column needs for its labels,
    // so that the diagram takes up the rest of the width.
    var last = visible[visible.length - 1];
    var ruler = document.createElement("canvas").getContext("2d");
    ruler.font = data.label_size + "px " + data.font;
    var longest = d3.max(last.levels.filter(function(l) { return last.selected.indexOf(l) >= 0; }),
                         function(l) { return ruler.measureText(l).width; }) || 0;
    options.margin = { top: x.options.margin.top, bottom: x.options.margin.bottom, left: x.options.margin.left,
                       right: Math.ceil(longest + data.label_room) };

    // The last column is placed at the right-hand edge. Left to itself the
    // widget keeps one column width empty there. Every path runs through every
    // column, so only last-column nodes are moved by this.
    options.sinksRight = true;
    if (split) options.nodePadding = data.lane_padding;

    binding.renderValue(el, {
      links: { source: list.map(function(l) { return l.source; }),
               target: list.map(function(l) { return l.target; }),
               value:  list.map(function(l) { return l.value; }),
               group:  list.map(groupOf),
               id:     list.map(function(l) { return l.id; }),
               n:      list.map(function(l) { return l.n; }) },
      nodes: { name: names, group: groups },
      options: options
    }, instance);

    polish(c, lanes);
  }

  // ---- Labels, column titles and hover, applied after each draw ------------------------
  function polish(c, lanes) {
    var svg   = d3.select(el).select("svg");
    var links = svg.selectAll(".link");
    var nodes = svg.selectAll(".node");
    var plot  = d3.select(nodes.node().parentNode);
    var first = c.visible[0];

    // The number of records in a node, whatever the widths are drawn as.
    function recordsIn(d) {
      return Math.max(d3.sum(d.sourceLinks, function(l) { return l.n; }),
                      d3.sum(d.targetLinks, function(l) { return l.n; }));
    }
    function laneOf(d) { return lanes[nodes.data().indexOf(d)]; }
    function pct(n, of) { return (100 * n / of).toFixed(1) + "%"; }
    // A node is given as a share of the records drawn or, with lanes drawn as
    // percents, of its own lane. First-column nodes are always shares of all records.
    function nodeShare(d, long) {
      var lane = laneOf(d);
      if (percent && lane) return pct(recordsIn(d), c.laneDrawn[lane]) + (long ? " of " + lane : "");
      return pct(recordsIn(d), c.drawn) + (percent ? " of all " + data.unit : "");
    }

    svg.selectAll("title").remove();

    // The widget shrinks its drawing to fit a box worked out from the labels,
    // which leaves empty space at the side. That box is removed, so that the
    // diagram is drawn at full size across the width given to it.
    svg.attr("viewBox", null);

    // Each flow is redrawn as a filled band with the same edges. Drawn as a
    // thick line, a wide flow bulges past its node where it bends; a filled
    // band cannot.
    function band(d, part) {
      var x0 = d.source.x + d.source.dx, x1 = d.target.x, xm = (x0 + x1) / 2;
      var w  = Math.max(1, d.dy) * (part === undefined ? 1 : part);
      var y0 = d.source.y + d.sy, y1 = d.target.y + d.ty;
      return "M" + x0 + "," + y0 +
             "C" + xm + "," + y0 + " " + xm + "," + y1 + " " + x1 + "," + y1 +
             "L" + x1 + "," + (y1 + w) +
             "C" + xm + "," + (y1 + w) + " " + xm + "," + (y0 + w) + " " + x0 + "," + (y0 + w) + "Z";
    }
    links.each(function(d) {
      var flow = d3.select(this);
      var colour = flow.style("stroke");
      d.colour = colour;
      flow.attr("d", band(d)).style("fill", colour).style("stroke", "none").style("fill-opacity", base);
    });

    // Dragging a node would redraw its flows as lines again, so it is switched off.
    nodes.on(".drag", null);
    nodes.select("rect").style("stroke", "none").style("cursor", "pointer");

    // Every label sits to the right of its node, including in the last column,
    // where it runs out into the right margin. Labels of neighbouring columns
    // then never share a gap. A pale outline keeps the text readable over the
    // flows, and each label carries its share of the records drawn.
    nodes.select("text")
      .attr("x", function(d) { return d.dx + 6; })
      .attr("text-anchor", "start")
      .style("fill", "#2a2520")
      .style("paint-order", "stroke")
      .style("stroke", data.background)
      .style("stroke-width", "3px")
      .style("stroke-linejoin", "round")
      .style("display", function(d) {
        return (split && d.dy < data.min_label_height) ? "none" : null;
      })
      .each(function(d) {
        d3.select(this).append("tspan")
          .attr("dx", 6)
          .style("fill", "#6f6a64")
          .style("font-size", (data.label_size - 2) + "px")
          .text(nodeShare(d, false));
      });

    // A title above each column.
    var columns = [];
    nodes.data().forEach(function(d) { if (columns.indexOf(d.x) < 0) columns.push(d.x); });
    columns.sort(function(a, b) { return a - b; });

    columns.forEach(function(cx, i) {
      plot.append("text")
        .attr("x", cx)
        .attr("y", -14)
        .attr("text-anchor", "start")
        .style("font-family", data.font)
        .style("font-size", (data.label_size - 1) + "px")
        .style("font-weight", 700)
        .style("letter-spacing", "0.4px")
        .style("fill", navy)
        .text(c.visible[i] ? c.visible[i].title : "");
    });

    // The records behind a node are followed exactly. The page holds whole
    // paths, so the records that pass through a node can be picked out, and the
    // share of every flow that they make up is drawn over the faded diagram.
    // Hovering shows the trace; clicking the node keeps it until the node is
    // clicked again.
    var pinned = null;
    var faded  = 0.13;

    function recordsThrough(d) {
      var lane = lanes[nodes.data().indexOf(d)], k = columns.indexOf(d.x);
      return c.kept.filter(function(p) {
        return p.levels[k] === d.name && (!lane || p.levels[0] === lane);
      });
    }

    function clearTrace() {
      plot.selectAll(".trace").remove();
      links.style("fill-opacity", base);
      if (legend) d3.select(legend).selectAll(".sankey-traced").remove();
    }

    function showTrace(d) {
      clearTrace();
      var part = c.flowsOf(recordsThrough(d));
      links.style("fill-opacity", faded);
      links.each(function(l) {
        var n = part[l.id];
        if (!n) return;
        // The trace goes in above the flows but beneath the nodes, so that the
        // node labels, which lie over the flows, stay readable on top of it.
        d3.select(this.parentNode).insert("path", ".node")
          .attr("class", "trace")
          .attr("d", band(l, n / l.n))
          .style("fill", l.colour)
          .style("fill-opacity", 0.95)
          .style("stroke", "none")
          .style("pointer-events", "none");
      });
    }

    function nodeTitle(d) {
      var lane = lanes[nodes.data().indexOf(d)];
      return (lane ? lane + " \\u2192 " : "") + d.name;
    }

    nodes
      .on("mouseover", function(d) {
        if (!pinned) showTrace(d);
        show("<strong>" + nodeTitle(d) + "</strong><br/>" +
             count(recordsIn(d)) + " " + data.unit + " (" + nodeShare(d, true) + ")");
      })
      .on("mousemove", move)
      .on("mouseout", function() { if (!pinned) clearTrace(); hide(); })
      .on("click", function(d) {
        if (pinned === d) { pinned = null; clearTrace(); return; }
        pinned = d;
        showTrace(d);
        if (legend) {
          d3.select(legend).append("span")
            .attr("class", "sankey-traced")
            .text("Following " + nodeTitle(d) + ": " + count(recordsIn(d)) + " " + data.unit +
                  " (click the node again to clear)");
        }
      });

    links
      .on("mouseover", function(d) {
        var origin = first.levels[parseInt(String(d.group).slice(1), 10)];
        var from = [origin, viaOf[d.group]].filter(function(name) {
          return name && name !== d.source.name && name !== d.target.name;
        });
        if (!pinned) links.style("fill-opacity", function(l) { return l === d ? 1 : 0.18; });
        show("<strong>" + d.source.name + " \\u2192 " + d.target.name + "</strong><br/>" +
             (from.length ? from.join(", ") + ": " : "") +
             count(d.n) + " " + data.unit + " (" +
             (percent ? pct(d.n, c.laneDrawn[origin]) + " of " + origin : pct(d.n, c.drawn)) + ")");
      })
      .on("mousemove", move)
      .on("mouseout", function() { if (!pinned) links.style("fill-opacity", base); hide(); });
  }

  // ---- Colour key, level counts and note ---------------------------------------------------
  // The colour key and the count shown on each list of levels belong to the
  // controls. They are filled in again after every change.
  var keyEl = null, countEls = {}, openKey = null;

  function refreshHeader() {
    var first = displayed()[0];

    // The key sits beside the chooser that sets the colours.
    if (keyEl) {
      keyEl.innerHTML = "";
      first.levels.forEach(function(level, li) {
        if (first.selected.indexOf(level) < 0) return;
        var item = document.createElement("span");
        var square = document.createElement("span");
        square.className = "sankey-swatch";
        square.style.background = first.colours[li];
        item.appendChild(square);
        item.appendChild(document.createTextNode(level));
        keyEl.appendChild(item);
      });
    }

    // Under each variable name: how many of its levels are included.
    stages.forEach(function(s) {
      if (!countEls[s.key]) return;
      countEls[s.key].textContent = s.selected.length === s.levels.length
        ? "All " + s.levels.length + " levels"
        : s.selected.length + " of " + s.levels.length + " levels";
    });
  }

  function writeLegend(c) {
    if (legend) legend.innerHTML = "";   // the line naming a node that is being followed
    refreshHeader();
  }

  function writeNote(c) {
    if (!noteEl) return;
    var text = [percent
      ? "Every lane is drawn to the same height, so the width of a band is its percent of the lane, " +
        "and the percents on the labels are percents of the lane."
      : "The width of a band is its number of " + data.unit + "."];

    if (split && data.lane_shading !== "none" && c.visible.length > 2) {
      text.push(data.lane_shading === "second"
        ? "Within a lane the shade is the " + c.visible[1].title.toLowerCase() + ", lightest for " +
          c.visible[1].levels[0] + " to darkest for " + c.visible[1].levels[c.visible[1].levels.length - 1] + "."
        : "Within a lane the shade is the level a flow has just left, lightest for the top level of a column.");
    }

    text.push("Shows " + count(c.drawn) + " of " + count(data.total_records) +
              " filtered records (" + (100 * c.drawn / data.total_records).toFixed(1) + "%).");

    var limited = stages
      .filter(function(s) { return s.selected.length < s.levels.length; })
      .map(function(s) {
        return s.title + ": " +
          s.levels.filter(function(l) { return s.selected.indexOf(l) >= 0; }).join(", ");
      });
    if (limited.length) text.push("Limited to " + limited.join("; ") + ".");

    var gaps = c.visible
      .filter(function(s) { return !s.keep_missing && s.missing_pct > data.note_threshold_pct; })
      .map(function(s) { return s.title + " (" + s.missing_pct + "%)"; });
    text.push("Records with no recorded value in a displayed variable are not shown" +
      (gaps.length ? "; missing for more than " + data.note_threshold_pct +
                     "% of records: " + gaps.join("; ") : "") + ".");

    if (c.shown - c.drawn > 0) {
      text.push((percent && minPct > 0
        ? "Flows smaller than " + minPct + "% of their lane, or of fewer than " +
          count(data.min_link_n) + " records, are not drawn ("
        : "Flows of fewer than " + count(Math.ceil(c.cutoff)) + " records are not drawn (") +
        count(c.shown - c.drawn) + " records in all).");
    }
    noteEl.textContent = text.join(" ");
  }

  // ---- The controls ----------------------------------------------------------------------
  // Two groups. The first is one line that sets how the diagram is drawn. The
  // second names the variables, in the left-to-right order of the columns:
  // each has a switch that shows or hides its column, and a list of its levels
  // that drops down beneath the name. A switch is used for the columns and tick
  // boxes for the levels, so that the two are not mistaken for each other.
  function buildControls() {
    if (!panel) return;

    // The controls are rebuilt after most changes; the control in use is found
    // again afterwards so that keyboard focus is not lost.
    var inUse = (document.activeElement && panel.contains(document.activeElement))
      ? document.activeElement.getAttribute("data-control") : null;
    panel.innerHTML = "";

    function tickBox(name) {
      var box = document.createElement("input");
      box.type = "checkbox";
      box.setAttribute("data-control", name);
      return box;
    }

    // A tick box inside its label, with an optional colour square.
    function labelled(box, text, colour) {
      var item = document.createElement("label");
      item.appendChild(box);
      if (colour) {
        var square = document.createElement("span");
        square.className = "sankey-swatch";
        square.style.background = colour;
        item.appendChild(square);
      }
      item.appendChild(document.createTextNode(text));
      return item;
    }

    var lead = displayed()[0];

    // ---- First group: how the diagram is drawn ---------------------------------------------
    var layout = document.createElement("div");
    layout.className = "sankey-layout";
    layout.setAttribute("role", "group");
    layout.setAttribute("aria-label", "How the diagram is drawn");

    var chooser = document.createElement("label");
    chooser.appendChild(document.createTextNode("Start with"));
    var select = document.createElement("select");
    select.setAttribute("data-control", "start");
    stages.forEach(function(s) {
      var option = document.createElement("option");
      option.value = s.key;
      option.textContent = s.title;
      option.selected = s.key === firstKey;
      select.appendChild(option);
    });
    select.value = firstKey;
    select.onchange = function() {
      firstKey = select.value;
      // Choosing a hidden variable switches it on.
      stages.forEach(function(s) { if (s.key === firstKey) s.on = true; });
      buildControls();
      redraw();
    };
    chooser.appendChild(select);
    layout.appendChild(chooser);

    keyEl = document.createElement("span");
    keyEl.className = "sankey-key";
    layout.appendChild(keyEl);

    var splitBox = tickBox("split");
    splitBox.checked = split;
    splitBox.onchange = function() {
      split = splitBox.checked;
      if (!split) percent = false;
      buildControls();
      redraw();
    };
    var splitItem = labelled(splitBox, "Split by first column");

    var percentBox = tickBox("percent");
    percentBox.checked = percent;
    percentBox.disabled = !split;
    percentBox.onchange = function() {
      percent = percentBox.checked;
      redraw();
    };
    var percentItem = labelled(percentBox, "Show as percent of lane");
    if (!split) percentItem.className = "off";

    var small = document.createElement("label");
    small.appendChild(document.createTextNode("Hide flows under"));
    var smallSelect = document.createElement("select");
    smallSelect.setAttribute("data-control", "small");
    var choices = [0, 0.01, 0.05, 0.1, 0.25, 0.5, 1, 2, 5];
    [+data.min_link_pct, minPct].forEach(function(v) { if (choices.indexOf(v) < 0) choices.push(v); });
    choices.sort(function(a, b) { return a - b; });
    choices.forEach(function(v) {
      var option = document.createElement("option");
      option.value = v;
      option.textContent = v + "%";
      option.selected = v === minPct;
      smallSelect.appendChild(option);
    });
    smallSelect.value = minPct;
    smallSelect.onchange = function() {
      minPct = +smallSelect.value;
      redraw();
    };
    small.appendChild(smallSelect);

    // The three options that set how the flows are drawn stay together when the
    // line wraps: the percent chooser, then the two tick boxes beside it.
    var options = document.createElement("span");
    options.className = "sankey-options";
    options.appendChild(small);
    options.appendChild(splitItem);
    options.appendChild(percentItem);
    layout.appendChild(options);

    var reset = document.createElement("button");
    reset.type = "button";
    reset.className = "sankey-reset";
    reset.setAttribute("data-control", "reset");
    reset.textContent = "Reset view";
    reset.onclick = function() {
      stages.forEach(function(s) { s.on = s.on_default; s.selected = s.levels.slice(); });
      firstKey = stages.filter(function(s) { return s.on; })[0].key;
      split    = data.keep_lanes;
      percent  = split && data.lane_percent;
      minPct   = +data.min_link_pct;
      buildControls();
      redraw();
    };
    layout.appendChild(reset);
    panel.appendChild(layout);

    // ---- Second group: the variables, always named, each with its levels -----------------------
    var variables = document.createElement("div");
    variables.className = "sankey-variables";
    countEls = {};

    [lead].concat(stages.filter(function(s) { return s !== lead; })).forEach(function(s) {
      var block = document.createElement("div");
      block.className = "sankey-variable" + (s.on ? "" : " off");

      // The name, with the switch for its column.
      var name = document.createElement("label");
      name.className = "sankey-variable-name";
      var toggle = tickBox("column-" + s.key);
      toggle.className = "sankey-switch";
      toggle.setAttribute("role", "switch");
      toggle.checked = s.on;
      toggle.onchange = function() {
        // A Sankey needs at least two columns.
        if (!toggle.checked && stages.filter(function(t) { return t.on; }).length <= 2) {
          toggle.checked = true;
          return;
        }
        s.on = toggle.checked;
        redraw();
        buildControls();   // keeps the chooser and the order in step when the first column is hidden
      };
      name.appendChild(toggle);
      name.appendChild(document.createTextNode(s.title));
      block.appendChild(name);

      // The levels, in a list that drops down beneath the name.
      var list = document.createElement("details");
      list.className = "sankey-levels";
      list.open = openKey === s.key;
      var summary = document.createElement("summary");
      summary.setAttribute("data-control", "levels-" + s.key);
      countEls[s.key] = summary;
      list.appendChild(summary);
      list.addEventListener("toggle", function() {
        if (list.open) {
          openKey = s.key;
          // Only one list is open at a time.
          var others = variables.querySelectorAll("details[open]");
          for (var i = 0; i < others.length; i++) if (others[i] !== list) others[i].open = false;
        } else if (openKey === s.key) {
          openKey = null;
        }
      });

      var group = document.createElement("fieldset");
      group.setAttribute("aria-label", s.title + " levels");
      s.levels.forEach(function(level, li) {
        var levelBox = tickBox("level-" + s.key + "-" + li);
        levelBox.checked = s.selected.indexOf(level) >= 0;
        var item = labelled(levelBox, level, s === lead ? s.colours[li] : null);
        function paint() { item.className = levelBox.checked ? "" : "off"; }
        paint();
        levelBox.onchange = function() {
          var at = s.selected.indexOf(level);
          if (!levelBox.checked) {
            if (s.selected.length === 1) { levelBox.checked = true; return; }   // one level stays on
            s.selected.splice(at, 1);
          } else if (at < 0) {
            s.selected.push(level);
          }
          paint();
          redraw();
        };
        group.appendChild(item);
      });
      list.appendChild(group);
      block.appendChild(list);
      variables.appendChild(block);
    });
    panel.appendChild(variables);

    refreshHeader();

    if (inUse) {
      var controls = panel.querySelectorAll("[data-control]");
      for (var i = 0; i < controls.length; i++) {
        if (controls[i].getAttribute("data-control") === inUse) { controls[i].focus(); break; }
      }
    }
  }

  // If the pieces needed for redrawing are missing, the diagram drawn by R is
  // left as it is.
  if (!binding || !instance) return;

  // The diagram keeps a workable height on a short window, and is redrawn to
  // fit when the window changes size.
  el.style.minHeight = "560px";

  // An open list of levels is closed by a click anywhere outside it, or by the
  // Escape key, which also hands focus back to the list.
  document.addEventListener("click", function(event) {
    if (!panel) return;
    var open = panel.querySelectorAll("details[open]");
    for (var i = 0; i < open.length; i++) if (!open[i].contains(event.target)) open[i].open = false;
  });
  document.addEventListener("keydown", function(event) {
    if (event.key !== "Escape" || !panel) return;
    var open = panel.querySelector("details[open]");
    if (open) { open.open = false; open.querySelector("summary").focus(); }
  });
  var resizeTimer = null;
  window.addEventListener("resize", function() {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(redraw, 200);
  });

  buildControls();
  redraw();
}
'

# ---- The builder -------------------------------------------------------------------
# paths               the path table: a column for each variable, and a count column n
# stages              a list with one entry per variable, in left-to-right order.
#                     Each entry is a list with:
#                       key           the column name in the path table
#                       title         the name shown above the column
#                       levels        the levels to show, in top-to-bottom order
#                       colours       one colour per level, used for the flows when
#                                     this variable is the first column
#                       on            TRUE to show the column when the page opens
#                       keep_missing  TRUE when "Not recorded" is one of the levels
#                       missing_pct   percent of records with no recorded value
# title, subtitle     shown in the header above the diagram
# total_records       the number of records in the path table
# note_threshold_pct  a displayed variable missing for more than this percent of
#                     records is named in the note
# min_link_pct        paths running through a flow smaller than this percent of the
#                     records shown are not drawn. This is the value the page
#                     opens with; a chooser on the page changes it
# min_link_n          paths running through a flow with fewer records than this are
#                     not drawn either, whatever the percent is set to
# unit                the word used for counts
# width, height       size of the diagram. A width of "100%" fills the page width;
#                     a height such as "82vh" is that percent of the window height

build_sankey <- function(paths, stages, title, subtitle,
                         total_records = sum(paths$n), note_threshold_pct = 10,
                         min_link_pct = 0, min_link_n = 0, unit = "records",
                         width = "100%", height = "82vh", node_padding = 16) {

  # One colour per level; a level with none is given a fallback.
  stages <- map(stages, function(s) {
    colours <- if (is.null(names(s$colours))) s$colours else unname(s$colours[s$levels])
    if (length(colours) != length(s$levels)) colours <- rep(NA_character_, length(s$levels))
    colours[is.na(colours)] <- rep_len(sankey_fallback_colours, sum(is.na(colours)))
    s$colours <- colours
    s
  })

  # ---- The opening view, drawn by R ------------------------------------------------
  # The browser redraws this at once; it is what remains if the redraw cannot run.
  visible <- keep(stages, \(s) isTRUE(s$on))
  keys    <- map_chr(visible, "key")
  first   <- visible[[1]]

  shown <- paths
  for (s in visible) shown <- shown[shown[[s$key]] %in% s$levels, ]

  nodes <- map(seq_along(visible), function(k) {
    present <- intersect(visible[[k]]$levels, shown[[keys[k]]])
    tibble(stage = k, level = present,
           group = if (k == 1) paste0("o", match(present, first$levels) - 1) else "mid")
  }) |>
    bind_rows() |>
    mutate(id = row_number() - 1)

  node_id <- function(stage, level) nodes$id[match(paste(stage, level), paste(nodes$stage, nodes$level))]

  links <- map(seq_len(length(keys) - 1), function(k) {
    tibble(stage = k, source = shown[[keys[k]]], target = shown[[keys[k + 1]]],
           origin = shown[[keys[1]]], value = shown$n) |>
      group_by(stage, source, target, origin) |>
      summarise(value = sum(value), .groups = "drop")
  }) |>
    bind_rows() |>
    mutate(
      source_id = node_id(stage, source),
      target_id = node_id(stage + 1, target),
      group     = paste0("l", match(origin, first$levels) - 1)
    ) |>
    arrange(source_id, target_id, group)

  origin_ids <- seq_along(first$levels) - 1

  colour_js <- sprintf(
    "d3.scaleOrdinal().domain(%s).range(%s)",
    jsonlite::toJSON(c(paste0("o", origin_ids), paste0("l", origin_ids), "mid")),
    jsonlite::toJSON(c(first$colours, first$colours, sankey_node_colour))
  )

  widget <- networkD3::sankeyNetwork(
    Links       = as.data.frame(select(links, source = source_id, target = target_id,
                                       value, group)),
    Nodes       = as.data.frame(select(nodes, name = level, group)),
    Source      = "source",
    Target      = "target",
    Value       = "value",
    NodeID      = "name",
    NodeGroup   = "group",
    LinkGroup   = "group",
    colourScale = htmlwidgets::JS(colour_js),
    fontSize    = sankey_label_size,
    fontFamily  = sankey_font,
    nodeWidth   = 18,
    nodePadding = node_padding,
    sinksRight  = TRUE,   # the last column sits at the right-hand edge
    iterations  = 0,      # keeps the nodes in the order given
    width       = width,
    height      = height,
    margin      = list(top = 36, right = 200, bottom = 10, left = 10)   # right: last column's labels
  )

  # ---- Header: title, subtitle, and empty holders the browser fills in -----------------
  css <- sankey_css
  css <- gsub("FONT",  sankey_font,        css, fixed = TRUE)
  css <- gsub("NAVY",  sankey_node_colour, css, fixed = TRUE)
  css <- gsub("MUTED", sankey_muted,       css, fixed = TRUE)

  header <- htmltools::tags$div(
    class = "sankey-head",
    htmltools::tags$style(htmltools::HTML(css)),
    htmltools::tags$h3(title),
    htmltools::tags$p(class = "sankey-subtitle", subtitle),
    htmltools::tags$div(class = "sankey-controls"),
    htmltools::tags$div(class = "sankey-legend")
  )

  note <- htmltools::tags$p(
    class = "sankey-note",
    paste0("Shows ", format(sum(shown$n), big.mark = ",", scientific = FALSE, trim = TRUE),
           " of ", format(total_records, big.mark = ",", scientific = FALSE, trim = TRUE),
           " filtered records.")
  )

  widget <- widget |>
    htmlwidgets::prependContent(header) |>
    htmlwidgets::appendContent(note)

  # ---- Everything the browser needs to redraw ----------------------------------------------
  all_keys <- map_chr(stages, "key")

  htmlwidgets::onRender(
    widget, sankey_explorer_js,
    data = list(
      stages = map(stages, function(s) {
        list(key = s$key, title = s$title, levels = as.list(s$levels),
             colours = as.list(s$colours), on = isTRUE(s$on), on_default = isTRUE(s$on),
             keep_missing = isTRUE(s$keep_missing), missing_pct = s$missing_pct)
      }),
      paths              = map(as.list(paths[c(all_keys, "n")]), as.list),
      total_records      = total_records,
      note_threshold_pct = note_threshold_pct,
      min_link_pct       = min_link_pct,
      min_link_n         = min_link_n,
      unit               = unit,
      font               = sankey_font,
      background         = sankey_background,
      node_colour        = sankey_node_colour,
      band_opacity       = sankey_band_opacity,
      keep_lanes         = sankey_keep_lanes,
      lane_padding       = sankey_lane_padding,
      min_label_height   = sankey_min_label_height,
      lane_shading       = sankey_lane_shading,
      lane_percent       = sankey_lane_percent,
      label_room         = sankey_label_room,
      label_size         = sankey_label_size,
      node_colours       = sankey_node_colours
    )
  )
}
