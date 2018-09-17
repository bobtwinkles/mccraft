'use strict';
const d3 = require('d3');

const Elm = require('./elm/Main.elm');

const CIRCLE_RADIUS = 30;

window.onload = function() {
    console.log('Document loaded');

    const container = d3.select('#d3container');
    const svg = container.select('svg');
    var width = container.node().offsetWidth;
    var height = document.body.clientHeight *9 / 10;
    if (height < width) {
        width = height;
    }
    console.log(width, height);
    // svg.attr('width', width);
    // svg.attr('height', height);

    const simulation = d3.forceSimulation();
    simulation
        .force('link', d3.forceLink()
            .id(function(d) {
                return d.id;
            })
            .distance(CIRCLE_RADIUS * 3))
        .force('collision', d3.forceCollide(CIRCLE_RADIUS))
        .force('charge', d3.forceManyBody())
        .force('center', d3.forceCenter());
    simulation.on('tick', ticked);
    simulation.on('end', ticked);

    const graph = {
        edges: [],
        nodes: [],
        nodeIdMap: {},
        edgeIdMap: {},
    };

    const zoomBehavior = d3.zoom();
    zoomBehavior.on('zoom', zoomed);

    svg.call(zoomBehavior);

    svg.append('pattern')
        .attr('patternUnits', 'userSpaceOnUse')
        .attr('id', 'bgpat')
        .attr('width', 100)
        .attr('height', 100)
        .append('image')
        .attr('xlink:href', '/static/static/img/textured-bg.png')
        .attr('width', 100)
        .attr('height', 100)
        .attr('image-rendering', 'pixelated');

    svg.append('rect')
        .attr('x', -500)
        .attr('y', -500)
        .attr('width', 1000)
        .attr('height', 1000)
        .attr('fill', 'url(#bgpat)');

    var root = svg.append('g');
    var link = root.append('g').attr('class', 'links').selectAll('.link');
    var node = root.append('g').attr('class', 'nodes').selectAll('.node');

    function restart() {
        node = node.data(graph.nodes, function(d) {
            return d.id;
        });
        node.exit().remove();
        var node_groups = node.enter()
            .append('g')
            .attr('class', 'node');

        // Slightly less than sqrt(2) to get some breathing room
        const IMAGE_SIZE = CIRCLE_RADIUS * 1.1;
        node_groups
            .append('circle')
            .attr('r', CIRCLE_RADIUS);
        node_groups
            .append('image')
            .attr('width', IMAGE_SIZE)
            .attr('height', IMAGE_SIZE)
            .attr('transform',
                'translate(' + (-IMAGE_SIZE / 2) + ',' + (-IMAGE_SIZE / 2) + ')')
            .attr('xlink:href', '/images/items/minecraft_diamond_sword_0.png');

        node = node_groups.merge(node);

        link = link.data(graph.edges, function(d) {
            return d.id;
        });
        link.exit().remove();
        link = link.enter().append('line')
            .attr('class', 'link')
            .merge(link);

        simulation.nodes(graph.nodes);
        simulation.force('link').links(graph.edges);
        simulation.alpha(1).restart();
    }


    function ticked() {
        link
            .attr("x1", function(d) {
                return d.source.x;
            })
            .attr("y1", function(d) {
                return d.source.y;
            })
            .attr("x2", function(d) {
                return d.target.x;
            })
            .attr("y2", function(d) {
                return d.target.y;
            });

        node
            .attr('transform', function(d) {
                return 'translate(' + d.x + ',' + d.y + ')';
            });

        checkForOutOfBounds();
    }

    function zoomed() {
        console.log('Zoomed');
        console.log(d3.event);
        root.attr('transform', d3.event.transform);
        checkForOutOfBounds();
    }

    function checkForOutOfBounds() {
        
    }

    const app = Elm.Elm.Main.init({
        node: document.getElementById('main')
    });


    app.ports.edgeOut.subscribe(function(data) {
        console.log(data);

        data.source = graph.nodeIdMap[data.source];
        data.target = graph.nodeIdMap[data.target];
        if (data.source === undefined || data.target === undefined) {
            console.log("Got invalid edge, bailing");
            return;
        }

        graph.edges.push(data);

        restart();
    });

    app.ports.nodeOut.subscribe(function(data) {
        console.log("Adding new node");
        graph.nodes.push(data);

        graph.nodeIdMap[data.id] = data;

        restart();
    });
    restart();
};
