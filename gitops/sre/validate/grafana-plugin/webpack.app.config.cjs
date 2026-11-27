const path = require('path');

module.exports = {
  mode: 'production',

  entry: path.resolve(
    __dirname,
    '../grafana-backend/src/module.ts'
  ),

  output: {
    path: path.resolve(
      __dirname,
      '../grafana-backend/dist'
    ),
    filename: 'module.js',
    libraryTarget: 'amd',
    clean: false
  },

  externalsType: 'amd',

  externals: {
    '@grafana/data': '@grafana/data'
  },

  resolve: {
    extensions: ['.ts', '.js'],
    modules: [
      path.resolve(__dirname, 'node_modules'),
      'node_modules'
    ]
  },

  module: {
    rules: [
      {
        test: /\.ts$/,
        use: path.resolve(
          __dirname,
          'app-typescript-loader.cjs'
        )
      }
    ]
  },

  devtool: false
};
