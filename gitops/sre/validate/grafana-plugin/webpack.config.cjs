const path = require('path');
const CopyPlugin = require('copy-webpack-plugin');

module.exports = {
  mode: 'production',

  entry: './src/module.ts',

  output: {
    path: path.resolve(__dirname, 'dist'),
    filename: 'module.js',
    library: {
      type: 'amd',
    },
    clean: true,
  },

  resolve: {
    extensions: ['.ts', '.tsx', '.js'],
  },

  module: {
    rules: [
      {
        test: /\.tsx?$/,
        exclude: /node_modules/,
        use: {
          loader: 'ts-loader',
          options: {
            compilerOptions: {
              noEmit: false,
              jsx: 'react',
            },
          },
        },
      },
    ],
  },

  externals: [
    'react',
    'react-dom',
    '@grafana/data',
    '@grafana/runtime',
    '@grafana/ui',
    '@grafana/schema',
    'rxjs',
  ],

  plugins: [
    new CopyPlugin({
      patterns: [
        {
          from: 'src/plugin.json',
          to: 'plugin.json',
        },
        {
          from: 'src/img',
          to: 'img',
        },
      ],
    }),
  ],

  devtool: false,
};
