const path = require('path');
const webpack = require('webpack');
const CopyWebpackPlugin = require('copy-webpack-plugin');
// const webpackMerge = require('webpack-merge');

const prod = 'production';
const dev = 'development';

// determine build env
const TARGET_ENV = process.env.NODE_ENV;
const isDev = TARGET_ENV == dev;
const isProd = TARGET_ENV == prod;

// entry and output path/filename variables
const entryPath = path.join(__dirname, 'src/static/index.js');
const outputPath = path.join(__dirname, 'dist');
const outputFilename = isProd ? '[name]-[hash].js' : '[name].js';

var plugins = [
    /*new ExtractTextPlugin({
        filename: 'static/css/[name]-[hash].css',
        allChunks: true,
    }),*/
    new CopyWebpackPlugin([{
        from: 'src/static/img/',
        to: 'static/img/'
    }, {
        from: 'src/favicon.ico'
    }, {
        from: 'src/style.css',
        to: ''
    }])
];

if (isProd) {
    plugins.push(new webpack.optimize.UglifyJsPlugin({
        minimize: true,
        compressor: {
            warnings: false
        }
        // mangle:  true
    }));
}

elmOptions = {};
if (isDev) {
    elmOptions.verbose = true;
    elmOptions.debug = true;
} else {
    elmOptions.verbose = true;
}

module.exports = {
    resolve: {
        extensions: ['.js', '.elm'],
        modules: ['node_modules']
    },
    module: {
        rules: [{
            test: /\.elm$/,
            exclude: [/elm-stuff/, /node_modules/],
            loader: 'elm-webpack-loader',
            options: elmOptions,
        }]
    },
    plugins: plugins,
};
