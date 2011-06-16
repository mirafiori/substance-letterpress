express = require('express')
app = express.createServer()
http = require('http')
fs = require('fs')
_ = require('underscore')
Data = require('data')
async = require('async')
LatexRenderer = require('./src/renderers').LatexRenderer
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

Util.fetchDocument = (url, callback) ->
  fragments = require('url').parse(url)
  options = { host: fragments.host, path: fragments.pathname }
  options.path += fragments.search if fragments.search

  http.get options, (cres) ->
    cres.setEncoding('utf8')
    json = ""
    cres.on 'data', (d) ->
      json += d
      
    cres.on 'end', ->
      callback(null, JSON.parse(json))
  .on 'error', (e) ->
    callback(e)

Util.convert = (url, options, callback) ->
  Util.fetchDocument url, (err, raw_doc) ->
    graph = new Data.Graph(schema)
    graph.merge(raw_doc.graph)
    doc = graph.get(raw_doc.id)
    
    new LatexRenderer(doc).render (latex) ->
      callback(null, latex)


# Routes
# -----------


# Index
app.get '/', (req, res) ->
  html = fs.readFileSync(__dirname+ '/templates/app.html', 'utf-8')
  res.send(html)

# Convert to LaTeX
app.get '/latex', (req, res) ->
  res.charset = 'utf8'
  res.header('Content-Type', 'text/plain')
  Util.convert req.query.url, {format: 'Latex'}, (err, latex) ->
    res.send(latex)

# On the fly PDF generation
app.get '/pdf', (req, res) ->
  pdfCmd = "pdflatex -halt-on-error -output-directory tmp tmp/document.tex"

  Util.convert req.query.url, {format: 'Latex'}, (err, latex) ->
    fs.writeFile 'tmp/document.tex', latex, 'utf8', (err) ->
      
      throw err if err
      exec pdfCmd, (err, stdout, stderr) ->
        console.log(stderr);
        if (err)
          # res.send('An error occurred during PDF generation. Be aware PDF export is highly experimental.
          #           So please help by reporting your problem to info@substance.io');
          res.send(stdout);
        else        
          fs.readFile 'tmp/document.pdf', (err, data) ->
            throw err if err
            res.writeHead(200, { 'Content-Type': 'application/pdf'})
            res.write(data, 'binary');
            res.end()


# Catch errors that may crash the server
process.on 'uncaughtException', (err) ->
  console.log('Caught exception: ' + err)

# setTimeout(function () {
#   console.log('This will still run.');
# }, 500);

# Start the fun
console.log('Letterpress is listening at http://localhost:4004')
app.listen(4004)

