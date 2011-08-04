express = require('express')
app = express.createServer()
http = require('http')
fs = require('fs')
_ = require('underscore')
Data = require('data')
async = require('async')
{LatexRenderer,PandocRenderer} = require('./src/renderers')
{spawn, exec} = require 'child_process'

# Express.js Configuration
# -----------

app.configure ->
  app.use(express.bodyParser())
  app.use(express.methodOverride())
  app.use(express.cookieParser())
  app.use(app.router)
  app.use(express.static(__dirname+"/public", { maxAge: 41 }))

# Fixtures
schema = JSON.parse(fs.readFileSync(__dirname+ '/data/schema.json', 'utf-8'))
raw_doc = JSON.parse(fs.readFileSync(__dirname+ '/data/document.json', 'utf-8'))


# Util
# -----------

Util = {}

Util.jsonToDocument = (raw_doc) ->
  graph = new Data.Graph(schema)
  graph.merge(raw_doc.graph)
  doc = graph.get(raw_doc.id)

Util.fetchDocument = (url, callback) ->
  fragments = require('url').parse(url)
  options = { host: fragments.hostname, port: fragments.port, path: fragments.pathname }

  options.path += fragments.search if fragments.search

  http.get options, (cres) ->
    cres.setEncoding('utf8')
    json = ""
    cres.on 'data', (d) ->
      json += d
      
    cres.on 'end', ->
      callback(null, Util.jsonToDocument(JSON.parse(json)))
  .on 'error', (e) ->
    callback(e)

Util.convert = (format, doc, callback) ->
  cmd = "./convert #{format}"
  process = exec cmd, (err, stdout, stderr) ->
    if err
      callback(new Error(stderr), null)
    else
      callback(null, stdout)
  
  pandocJson = new PandocRenderer(doc).render()
  process.stdin.end(JSON.stringify(pandocJson), 'utf-8')


# Fetch online resource (like an image)
# ##################

fetchResource = (url, id, index, callback) ->
  fragments = require('url').parse(url)
  options = { host: fragments.host, path: fragments.pathname }
  if (fragments.search)
    options.path += fragments.search
  
  
  out = fs.createWriteStream("tmp/#{id}/resources/#{index}.png", {encoding: 'binary'})
  
  http.get options, (cres) ->
    return callback('error', '') if (cres.statusCode != 200)
    cres.setEncoding('binary')
    cres.on 'data', (d) ->
      out.write(d, 'binary')
      
    cres.on 'end', ->
      out.end()
      callback()
      
  .on 'error', (e) ->
    callback(e)


# Fetch online resources (like an image)
# ##################

fetchResources = (resources, id, callback) ->
  index = 0
  async.forEach resources, (resource, callback) ->
      fetchResource resource, id, index, -> callback()
      index += 1
    , -> callback()


# Routes
# ------

# Index
app.get '/', (req, res) ->
  html = fs.readFileSync(__dirname+ '/templates/app.html', 'utf-8')
  res.send(html)

formats =
  latex: { mime: 'text/plain' } # actually text/x-latex
  markdown: { mime: 'text/plain' }
  html: { mime: 'text/html' }

app.get '/render', (req, res) ->
  {format, url} = req.query
  res.charset = 'utf8'
  sendError = (statusCode, error) ->
    res.statusCode = statusCode
    res.end(error.message)
  
  unless formats[format]
    # bad request
    sendError(400, new Error("Unknown target format.")); return
  Util.fetchDocument url, (err, doc) ->
    if err
      # not found
      sendError(404, err); return
    Util.convert format, doc, (err, result) ->
      if err
        # internal server error
        sendError(500, err); return
      console.log("Converted #{url} to #{format}.")
      res.header('Content-Type', formats[format].mime)
      res.end(result)

# On the fly PDF generation
#app.get '/pdf', (req, res) ->
#  
#  Util.convert req.query.url, {format: 'Latex'}, (err, latex, id, resources) ->
#    pdfCmd = "pdflatex -halt-on-error -output-directory tmp/#{id} tmp/#{id}/document.tex"
#    rmCmd = "rm -rf tmp/#{id}"
#    
#    # First remove tmp dir if still there
#    exec rmCmd, (err, stdout, stderr) ->
#      fs.mkdirSync("tmp/#{id}", 0755)
#      fs.mkdirSync("tmp/#{id}/resources", 0755)
#
#      fs.writeFile "tmp/#{id}/document.tex", latex, 'utf8', (err) ->
#        throw err if err
#      
#        fetchResources resources, id, ->
#        
#          exec pdfCmd, (err, stdout, stderr) ->
#            console.log(stderr)
#            if (err)
#              res.send('An error occurred during PDF generation. Be aware PDF export is highly experimental.
#                        Problems occur when special characters are used for example. Please help improving all this by reporting your particular problem to <a href="mailto:info@substance.io">info@substance.io</a>.')
#              # res.send(stdout)
#            else
#              fs.readFile "tmp/#{id}/document.pdf", (err, data) ->
#                throw err if err
#                res.writeHead(200, { 'Content-Type': 'application/pdf'})
#                res.write(data, 'binary')
#                exec rmCmd
#                res.end()


# Catch errors that may crash the server
process.on 'uncaughtException', (err) ->
  console.log('Caught exception: ' + err)


# Start the fun
console.log('Letterpress is listening at http://localhost:4004')
app.listen(4004)

