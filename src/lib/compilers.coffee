fs         = require 'fs'
path       = require 'path'
lessc      = require 'less'
browserify = require 'browserify'
Promise    = require 'bluebird'
mdeps      = require 'module-deps'
collect    = Promise.promisify(require 'collect-stream')
coffeeify  = require 'coffeeify'
through    = require 'through'
R          = require 'ramda'

Block = require './block'
File  = require './file'

readFile = Promise.promisify fs.readFile

class Compiler
  constructor: (@compileFn, @depsFn) ->
  run: ->
    Promise.all([
      R.apply(@compileFn, arguments),
      R.apply(@depsFn, arguments).map (path) ->
        File.ctime(path).then (ctime) ->
          path:  path
          ctime: ctime
    ]).then R.zipObj(['content', 'dependencies'])

less = do ->
  lessRender = Promise.promisify(lessc.render)

  lessOptions = (platform, filePath) ->
    paths: [
      path.join(path.resolve(filePath, '../../../../'), 'const', platform)
      path.dirname filePath
    ]
    filename: filePath

  lessCompile = (platform, filePath) ->
    render = R.rPartial(lessRender, lessOptions(platform, filePath))
    readFile(filePath, encoding: 'utf-8').then(render)

  lessDependencies = (platform, filePath) ->
    parser = new lessc.Parser(lessOptions(platform, filePath))
    parse = Promise.promisify(parser.parse, parser)
    getFiles = -> R.append(filePath, R.keys(parser.imports.files))
    R.pPipe(readFile, parse, getFiles)(filePath, encoding: 'utf-8')

  new Compiler(lessCompile, lessDependencies)


js = do ->
  transformer = (f) -> () ->
    buffer = ''
    write  = (data) -> buffer += data
    end    = ->
      @queue f(buffer)
      @queue null
    through write, end

  include2require = transformer (js) ->
    js.replace /\/\/= include (.+)/g, 'require(\'./$1\');'

  imagePaths = (filePath) -> transformer (js) ->
    blockPath = path.resolve(filePath, '../../../..')
    relPath = path.relative(blockPath, path.resolve(filePath, '..'))
    js.replace /(['"])url\((?!\/)([^'"]+)\)/g, "$1url(/#{relPath}/$2)"

  jsCompile = (platform, filePath) ->
    new Promise (resolve, reject) ->
      browserify()
        .transform(coffeeify, include2require, imagePaths(filePath))
        .add(filePath)
        .bundle (err, data) ->
          if err? then reject err
          else resolve data.toString 'utf-8'

  jsDependencies = (platform, filePath) ->
    md = mdeps(transform: [coffeeify, include2require, imagePaths(filePath)])
    md.end filePath
    R.pPipe(collect, R.map(R.prop 'file'))(md)

  new Compiler(jsCompile, jsDependencies)


module.exports = {
  less
  js
}
