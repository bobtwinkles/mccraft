'use strict';
const d3 = require('d3');
const cola = require('webcola');

const Elm = require('./elm/Main.elm');

const CIRCLE_RADIUS = 30;

window.onload = function() {
    console.log('Document loaded');

    const container = d3.select('#d3container');
    const svg = container.select('svg');
    var width = container.node().offsetWidth;
    var height = document.body.clientHeight * 9 / 10;
    if (height < width) {
        width = height;
    }
    console.log(width, height);
    // svg.attr('width', width);
    // svg.attr('height', height);

    const graph = {
        edges: [],
        nodes: [],
        nodeIdMap: {},
        edgeIdMap: {},
    };

    var simulation = makeSim();

    const zoomBehavior = d3.zoom();
    zoomBehavior.on('zoom', zoomed);

    svg.call(zoomBehavior);

    var root = svg.append('g');
    var link = root.append('g').attr('class', 'links').selectAll('.link');
    var node = root.append('g').attr('class', 'nodes').selectAll('.node');

    svg.append('g')
        .append('rect')
        .attr('x', 5)
        .attr('y', 5)
        .attr('width', 30)
        .attr('height', 30)
        .attr('fill', '#000')
        .on('click', function(d) {
            svg.transition(5)
                .call(zoomBehavior.transform, d3.zoomIdentity);
        });

    function makeSim() {
        var sim = cola.d3adaptor(d3);

        sim
            .flowLayout("y", CIRCLE_RADIUS * 3)
            .jaccardLinkLengths(CIRCLE_RADIUS * 2)
            .start();

        sim.on('tick', ticked);
        sim.on('end', ticked);

        sim.nodes(graph.nodes);
        sim.links(graph.edges);

        return sim;
    }

    function restart() {
        node = node.data(graph.nodes, function(d) {
            return d.id;
        });
        node.exit().remove();
        var node_groups = node.enter()
            .append('g')
            .attr('class', 'node');

        var item_nodes = node_groups
            .filter(function(d) {
                return d.ty === "Item";
            });

        // fill item nodes with an image icon of the item
        // Slightly less than sqrt(2) to get some breathing room
        const IMAGE_SIZE = CIRCLE_RADIUS * 1.1;
        item_nodes
            .append('circle')
            .attr('r', CIRCLE_RADIUS);
        item_nodes
            .append('image')
            .attr('width', IMAGE_SIZE)
            .attr('height', IMAGE_SIZE)
            .attr('transform',
                'translate(' + (-IMAGE_SIZE / 2) + ',' + (-IMAGE_SIZE / 2) + ')')
            .attr('image-rendering', 'optimizespeed')
            .attr('xlink:href', function(d) {
                return d.imgUrl;
            });
        item_nodes.append('title')
            .text(function(d) {
                return d.name;
            });

        item_nodes.on('click', function(d) {
            app.ports.itemClicked.send(d.id);
        });

        item_nodes.call(simulation.drag);

        var recipe_nodes = node_groups
            .filter(function(d) {
                return d.ty === "Recipe";
            });

        recipe_nodes.on('click', function(d) {
            app.ports.removeRecipe.send(d.id);
        });

        recipe_nodes
            .append('rect');

        recipe_nodes
            .append('text')
            .attr('class', 'grid-recipe-text')
            .text(function(d) {
                return d.machineName;
            });

        recipe_nodes.selectAll('text').each(function(d) {
            d.bb = this.getBBox();
        });

        const RECT_PADDING = 8;
        recipe_nodes
            .selectAll('rect')
            .attr('width', function(d) {
                return d.bb.width + RECT_PADDING;
            })
            .attr('height', function(d) {
                return d.bb.height;
            })
            .attr('x', function(d) {
                return -(d.bb.width + RECT_PADDING) / 2;
            })
            .attr('y', function(d) {
                return -(d.bb.height + RECT_PADDING) / 2;
            })
            .attr('rx', RECT_PADDING)
            .attr('ry', RECT_PADDING)
            .classed('recipe-rect', true);

        node = node_groups.merge(node);

        link = link.data(graph.edges, getEdgeId);
        link.exit().remove();
        link = link.enter().append('path')
            .attr('class', 'link')
            .merge(link);

        simulation.start();
    }


    function ticked() {
        link
            .attr('d', function(d) {
                // mostly borrowed from the Cola D3 integration example
                var deltaX = d.target.x - d.source.x,
                    deltaY = d.target.y - d.source.y,
                    dist = Math.sqrt(deltaX * deltaX + deltaY * deltaY),
                    normX = deltaX / dist,
                    normY = deltaY / dist,
                    sourcePadding = CIRCLE_RADIUS,
                    targetPadding = CIRCLE_RADIUS + 12,
                    sourceX = d.source.x + (sourcePadding * normX),
                    sourceY = d.source.y + (sourcePadding * normY),
                    targetX = d.target.x - (targetPadding * normX),
                    targetY = d.target.y - (targetPadding * normY);
                return 'M' + sourceX + ',' + sourceY + 'L' + targetX + ',' + targetY;
            });

        node
            .attr('transform', function(d) {
                return 'translate(' + d.x + ',' + d.y + ')';
            });

        checkForOutOfBounds();
    }

    function zoomed() {
        root.attr('transform', d3.event.transform);
        checkForOutOfBounds();
    }

    function checkForOutOfBounds() {
        // TODO: display borders in the direction of the off-screen elements
    }

    const app = Elm.Elm.Main.init({
        node: document.getElementById('main')
    });


    document.getElementById('primary-search').onclick = function(event) {
        this.setSelectionRange(0, this.value.length);
    };

    var generation = 0;

    app.ports.graphOut.subscribe(function(data) {
        simulation.stop();

        generation = generation + 1;

        // Clear out the node and edge lists temporarily
        graph.nodes.length = 0;
        graph.edges.length = 0;

        // Make sure all the incoming nodes are in the various lists
        for (var i = 0; i < data.nodes.length; i++) {
            var node = data.nodes[i];

            if (node.id in graph.nodeIdMap) {
                graph.nodes.push(graph.nodeIdMap[node.id]);
            } else {
                graph.nodes.push(node);
                graph.nodeIdMap[node.id] = node;
            }

            graph.nodeIdMap[node.id].generation = generation;
        }

        // remove things that are not part of this generation of nodes from the
        // map so they don't get referenced by accident
        for (var nodeId in graph.nodeIdMap) {
            if (graph.nodeIdMap.hasOwnProperty(nodeId)) {
                if (graph.nodeIdMap[nodeId].generation === generation) {
                    continue;
                }
                delete graph.nodeIdMap[nodeId];
            }
        }

        // Do the same for the edges
        for (var i = 0; i < data.edges.length; i++) {
            var edge = data.edges[i];

            edge.source = graph.nodeIdMap[edge.source];
            edge.target = graph.nodeIdMap[edge.target];

            var edgeID = getEdgeId(edge);

            if (edgeID in graph.edgeIdMap) {
                graph.edges.push(graph.edgeIdMap[edgeID]);
            } else {
                graph.edges.push(edge);
                graph.edgeIdMap[edgeID] = edge;
            }

            graph.edgeIdMap[edgeID].generation = generation;
        }

        for (var edgeId in graph.edgeIdMap) {
            if (graph.edgeIdMap.hasOwnProperty(edgeId)) {
                if (graph.edgeIdMap[edgeId].generation === generation) {
                    continue;
                }
                delete graph.edgeIdMap[edgeId];
            }
        }

        restart();
        simulation.start();
    });

    function getEdgeId(edge) {
        return "s" + (edge.source.id) + "t" + (edge.target.id);
    }


    restart();
};
