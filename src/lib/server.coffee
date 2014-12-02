path      = require 'path'

express   = require 'express'
Promise   = require 'bluebird'
R         = require 'ramda'

Block     = require './block'
Compilers = require './compilers'
File      = require './file'
Cache     = require './cache'


createServer = (directory) ->
  app = express()
  cache = new Cache()

  app.get '/.build/blocks.*/*/*/*', (req, res) ->
    extensions =
      css: ['less']
      js: ['coffee', 'js']

    extCompilers =
      coffee: 'js'
      js: 'js'
      less: 'less'

    recompile = ->
      blockFile = Block.BlockFile.fromPath(req.path)

      filePaths = R.compose(R.flatten, R.map) (ext) ->
        [
          path.join(directory, blockFile.changeExtension(ext).toPath())
          path.join(directory, blockFile.changeExtension(ext).changePlatform('').toPath())
        ]
      , extensions[blockFile.extension]

      File.existsAny filePaths
        .then (filePath) ->
          compiler = extCompilers[path.extname(filePath)[1..]]
          type = blockFile.extension
          Compilers[compiler].run(blockFile.platform, filePath)
            .then (result) ->
              cache.update(req.path, new Cache.Entry(type, result.content, result.dependencies))
              res.type(type).send result.content
            .catch (err) ->
              console.error err
              res.status(500).send('Error: ' + err.message)
        .catch (err) ->
          console.log err
          res.status(404).end()

    if cache.has(req.path)
      cacheEntry = cache.get(req.path)
      cacheEntry.isValid().then (valid) ->
        if valid
          res.type(cacheEntry.mime).send(cacheEntry.content)
        else
          recompile()
    else
      recompile()

  app.use express.static(directory)
  app

module.exports = {
  createServer
}