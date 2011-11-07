#constants

CDG_DISPLAY_WIDTH = 294
CDG_DISPLAY_HEIGHT = 204
CDG_FRAME_WIDTH = 300
CDG_FRAME_HEIGHT = 216
CDG_TILE_WIDTH = 6
CDG_TILE_HEIGHT = 12
CDG_TILES_PER_ROW = CDG_FRAME_WIDTH / CDG_TILE_WIDTH
CDG_TILES_PER_COL = CDG_FRAME_HEIGHT / CDG_TILE_HEIGHT

#reader class for CD+G files
class CdgReader

  #index
  index: 0
  
  #length
  length: @binaryString.length
  
  #reset the stream
  reset: -> @index = 0

  constructor: (@chunkHandler, @binaryString) ->

  #read from the binary string and call the chunk handler
  #may not get a chunk every read  
  next: ->
    return false if @index >= @binaryString.length
    command = @binaryString.charAt @index
    if command is 0x09
      @index += 2
      switch command & 0x3f
        when 1
          #memory preset
          @chunkHandler.memoryPreset(
            #color index 
            @binaryString.charAt(++@index) & 0x0f,
            #repeat 
            @binaryString.charAt(++@index) & 0x0f)
          @index += 14
        when 2
          #border preset
          #color index
          @chunkHandler.borderPreset @binaryString.charAt(++@index) & 0x0f
          @index += 15
        when 6, 38
          #tile block
          @chunkHandler.tileBlock(
            #color index off
            @binaryString.charAt(++@index) & 0x0f,
            #color index on
            @binaryString.charAt(++@index) & 0x0f,
            #row
            @binaryString.charAt(++@index) & 0x1f,
            #column
            @binaryString.charAt(++@index) & 0x3f,
            #normal?
            command & 0x3f is 6,
            #pixels
            @_readAndMask 12, 0x3f)
        when 20
          #scroll preset
          @chunkHandler.scrollPreset(
            #color index
            @binaryString.charAt(++@index) & 0x0f,
            #horizontal scroll
            @binaryString.charAt(++@index) & 0x3f,
            #vertical scroll
            @binaryString.charAt(++@index) & 0x3f)
          @index += 13
        when 24
          #scroll copy
          @index++
          @chunkHandler.scrollCopy(
            #horizontal scroll
            @binaryString.charAt(++@index) & 0x3f,
            #vertical scroll
            @binaryString.charAt(++@index) & 0x3f)
          @index += 13
        when 28
          #define transparent color
          #color index
          @chunkHandler.defineTransparentColor @binaryString.charAt(++@index) & 0x3f
          @index += 15
        when 30, 31
          #load color table
          @chunkHandler.loadColorTable(
            #color table 
            @_readColorTable(),
            #is low?
            command & 0x3f is 30)
        else @index += 16
      @index += 4
      return true
            
  #read from binary string for certain number, mask, return array
  _readAndMask: (amount, mask) -> @binaryString.charAt(++@index) & mask for i in [1..amount]

  #read color table
  _readColorTable: ->
    for i in [0..7]
      one = @binaryString.charAt(++@index) & 0x3f
      two = @binaryString.charAt(++@index) & 0x3f
      red: ((one & 0x3f) >> 2) * 17,
      green: (((one & 0x3) << 2) | ((two & 0x3f) >> 4)) * 17,
      blue: (two & 0xf) * 17 

#base handler for reading
class CdgChunkHandler
  memoryPreset: (colorIndex, repeat) -> throw new Error 'Unimplemented'
  borderPreset: (colorIndex) -> throw new Error 'Unimplemented'
  tileBlock: (colorIndexOff, colorIndexOn, row, column, normal, pixels) ->
    throw new Error 'Unimplemented'
  scrollPreset: (colorIndex, horizontalScroll, verticalScroll) -> throw new Error 'Unimplemented'
  scrollCopy: (horizontalScroll, verticalScroll) -> throw new Error 'Unimplemented'
  defineTransparentColor: (colorIndex) -> throw new Error 'Unimplemented'
  loadColorTable: (colorTable, low) -> throw new Error 'Unimplemented'

#handler impl for buffered canvas
class CanvasCdgChunkHandler extends CdgChunkHandler
  
  #array of updates (which can be an array itself)
  _updates: []
  
  #current update index
  _renderIndex: 0
  
  #current set of indexes in the image (only used during load)
  _colorIndexes: [CDG_FRAME_WIDTH * CDG_FRAME_HEIGHT]
  
  #current set of colors in the image (only used during load)
  _colors: [16]
  
  constructor: (@context) ->
    #default the color table
    @_colors[i] = (red: 0, green: 0, blue: 0) for i in [0..15]
  
  memoryPreset: (colorIndex, repeat) ->
    update = []
    #set tile colors
    for y in [1..CDG_TILES_PER_COL - 1]
      for x in [1..CDG_TILES_PER_ROW - 1]
        update.push @_getTileColorUpdate y, x, colorIndex
    #add updates
    @_updates.push update
    #empty repeats
    @_updates.push null for i in [1..repeat - 1]
  
  borderPreset: (colorIndex) ->
    update = []
    for i in [0..CDG_TILES_PER_ROW - 1]
      update.push @_getTileColorUpdate 0, i, colorIndex
      update.push @_getTileColorUpdate CDG_TILES_PER_COL - 1, i, colorIndex
    for i in [0..CDG_TILES_PER_COL - 1]
      update.push @_getTileColorUpdate i, 0, colorIndex
      update.push @_getTileColorUpdate i, CDG_TILES_PER_ROW - 1, colorIndex
    @_updates.push update
      
  tileBlock: (colorIndexOff, colorIndexOn, row, column, normal, pixels) ->
    image = @context.createImageData CDG_TILE_WIDTH, CDG_TILE_HEIGHT
    data = image.getData()
    x = column * CDG_TILE_WIDTH
    y = row * CDG_TILE_HEIGHT
    dataIndex = 0
    colorValueIndex = y * CDG_FRAME_WIDTH + x
    for i in [0..pixels.length - 1]
      for j in [0..CDG_TILE_WIDTH]
        pix = (pixels[i] >>> (5 - j)) & 0x01
        colorIndex = if pix is 0 then colorIndexOff else colorIndexOn
        colorIndex ^= @_colorIndexes[colorIndex] if not normal
        data[dataIndex * 4] = @_colors[colorIndex].red
        data[dataIndex * 4 + 1] = @_colors[colorIndex].green
        data[dataIndex * 4 + 2] = @_colors[colorIndex].blue
        data[dataIndex * 4 + 3] = 255
        @_colorIndexes[colorValueIndex] = colorIndex
        dataIndex++
        colorValueIndex++
      colorValueIndex += CDG_FRAME_WIDTH - CDG_TILE_WIDTH
    @_updates.push
      x: x
      y: y
      image: image
      
  scrollPreset: (colorIndex, horizontalScroll, verticalScroll) ->
    #ignore
    @_updates.push null
    
  scrollCopy: (horizontalScroll, verticalScroll) ->
    #ignore
    @_updates.push null
    
  defineTransparentColor: (colorIndex) ->
    #ignore
    @_updates.push null
    
  loadColorTable: (colorTable, low) ->
    for i in [0..colorTable.length - 1]
      @_colors[if low then i else i + 8] = colorTable[i] if colorTable[i]?
    #refresh the existing color table
    image = @context.createImageData CDG_FRAME_WIDTH, CDG_FRAME_HEIGHT
    data = image.getData()
    for i in [0..CDG_FRAME_WIDTH * CDG_FRAME_HEIGHT - 1]
      data[i * 4] = @_colors[@_colorIndexes[i]].red
      data[i * 4 + 1] = @_colors[@_colorIndexes[i]].green
      data[i * 4 + 2] = @_colors[@_colorIndexes[i]].blue
      data[i * 4 + 3] = 255
    @_updates.push
      x: 0
      y: 0
      image: image
      
  reset: -> @_renderIndex = 0
  
  renderNext: ->
    return false if @_renderIndex >= @_updates.length
    update = @_updates[@_renderIndex]
    if update?
      if update instanceof Array
        @context.putImageData u.image, u.x, u.y for u in update
      else
        @context.putImageData update.image, update.x, update.y  
    @_renderIndex++
    return true
    
  _getTileColorUpdate: (row, column, colorIndex) ->
    image = @context.createImageData CDG_TILE_WIDTH, CDG_TILE_HEIGHT
    data = image.getData()
    dataIndex = 0
    colorValueIndex = (CDG_TILE_HEIGHT * row * CDG_FRAME_WIDTH) + (CDG_TILE_WIDTH * col)
    for i in [0..CDG_TILE_HEIGHT - 1]
      for j in [0..CDG_TILE_WIDTH - 1]
        data[dataIndex * 4] = @_colors[colorIndex].red
        data[dataIndex * 4 + 1] = @_colors[colorIndex].green
        data[dataIndex * 4 + 2] = @_colors[colorIndex].blue
        data[dataIndex * 4 + 3] = 255
        @_colorIndexes[colorValueIndex] = colorIndex
        dataIndex++
        colorValueIndex++
      colorValueIndex += CDG_FRAME_WIDTH - TILE_WIDTH
    x: CDG_TILE_WIDTH * column,
    y: CDG_TILE_HEIGHT * row,
    image: image







