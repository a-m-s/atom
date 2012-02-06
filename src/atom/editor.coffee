{View} = require 'space-pen'
Buffer = require 'buffer'
Point = require 'point'
Cursor = require 'cursor'
Selection = require 'selection'
Highlighter = require 'highlighter'
Range = require 'range'

$ = require 'jquery'
$$ = require 'template/builder'
_ = require 'underscore'

module.exports =
class Editor extends View
  @content: ->
    @div class: 'editor', tabindex: -1, =>
      @div outlet: 'lines'
      @input class: 'hidden-input', outlet: 'hiddenInput'

  vScrollMargin: 2
  hScrollMargin: 10
  cursor: null
  buffer: null
  selection: null
  lineHeight: null
  charWidth: null

  initialize: () ->
    requireStylesheet 'editor.css'
    requireStylesheet 'theme/twilight.css'
    @bindKeys()
    @buildCursorAndSelection()
    @handleEvents()
    @setBuffer(new Buffer)

  bindKeys: ->
    atom.bindKeys '*',
      right: 'move-right'
      left: 'move-left'
      down: 'move-down'
      up: 'move-up'
      'shift-right': 'select-right'
      'shift-left': 'select-left'
      'shift-up': 'select-up'
      'shift-down': 'select-down'
      enter: 'newline'
      backspace: 'backspace'
      delete: 'delete'
      'meta-x': 'cut'
      'meta-c': 'copy'
      'meta-v': 'paste'

    @on 'move-right', => @moveCursorRight()
    @on 'move-left', => @moveCursorLeft()
    @on 'move-down', => @moveCursorDown()
    @on 'move-up', => @moveCursorUp()
    @on 'select-right', => @selectRight()
    @on 'select-left', => @selectLeft()
    @on 'select-up', => @selectUp()
    @on 'select-down', => @selectDown()
    @on 'newline', =>  @insertNewline()
    @on 'backspace', => @backspace()
    @on 'delete', => @delete()
    @on 'cut', => @cutSelection()
    @on 'copy', => @copySelection()
    @on 'paste', => @paste()

  buildCursorAndSelection: ->
    @cursor = new Cursor(this)
    @append(@cursor)

    @selection = new Selection(this)
    @append(@selection)

  handleEvents: ->
    @on 'focus', =>
      @hiddenInput.focus()
      false

    @on 'mousedown', (e) =>
      clickCount = e.originalEvent.detail

      if clickCount == 1
        @setCursorPosition @pointFromMouseEvent(e)
      else if clickCount == 2
        @selection.selectWord()
      else if clickCount >= 3
        @selection.selectLine(@getCursorRow())

      @selectTextOnMouseMovement()

    @hiddenInput.on "textInput", (e) =>
      @insertText(e.originalEvent.data)

    @on 'cursor:position-changed', =>
      @hiddenInput.css(@pixelPositionFromPoint(@cursor.getPosition()))

    @one 'attach', =>
      @calculateDimensions()
      @hiddenInput.width(@charWidth)
      @focus()

  selectTextOnMouseMovement: ->
    moveHandler = (e) => @selectToPosition(@pointFromMouseEvent(e))
    @on 'mousemove', moveHandler
    $(document).one 'mouseup', => @off 'mousemove', moveHandler


  buildLineElement: (row) ->
    tokens = @highlighter.tokensForRow(row)
    $$.pre class: 'line', ->
      if tokens.length
        for token in tokens
          classes = token.type.split('.').map((c) -> "ace_#{c}").join(' ')
          @span { class: token.type.replace('.', ' ') }, token.value
      else
        @raw '&nbsp;'

  setBuffer: (@buffer) ->
    @highlighter = new Highlighter(@buffer)

    @lines.empty()
    for row in [0..@buffer.lastRow()]
      line = @buildLineElement(row)
      @lines.append line

    @setCursorPosition(row: 0, column: 0)

    @buffer.on 'change', (e) =>
      @cursor.bufferChanged(e)

    @highlighter.on 'change', (e) =>
      { preRange, postRange } = e

      if postRange.end.row > preRange.end.row
        # update, then insert elements
        for row in [preRange.start.row..postRange.end.row]
          if row <= preRange.end.row
            @updateLineElement(row)
          else
            @insertLineElement(row)
      else
        # traverse in reverse... remove, then update elements
        for row in [preRange.end.row..preRange.start.row]
          if row > postRange.end.row
            @removeLineElement(row)
          else
            @updateLineElement(row)

  updateLineElement: (row) ->
    @getLineElement(row).replaceWith(@buildLineElement(row))

  insertLineElement: (row) ->
    @getLineElement(row).before(@buildLineElement(row))

  removeLineElement: (row) ->
    @getLineElement(row).remove()

  getLineElement: (row) ->
    @lines.find("pre.line:eq(#{row})")

  clipPosition: ({row, column}) ->
    if row > @buffer.lastRow()
      row = @buffer.lastRow()
      column = @buffer.getLine(row).length
    else
      row = Math.min(Math.max(0, row), @buffer.numLines() - 1)
      column = Math.min(Math.max(0, column), @buffer.getLine(row).length)

    new Point(row, column)

  pixelPositionFromPoint: ({row, column}) ->
    { top: row * @lineHeight, left: column * @charWidth }

  pointFromPixelPosition: ({top, left}) ->
    { row: Math.floor(top / @lineHeight), column: Math.floor(left / @charWidth) }

  pointFromMouseEvent: (e) ->
    { pageX, pageY } = e
    @pointFromPixelPosition
      top: pageY - @lines.offset().top
      left: pageX - @lines.offset().left

  calculateDimensions: ->
    fragment = $('<pre style="position: absolute; visibility: hidden;">x</pre>')
    @lines.append(fragment)
    @charWidth = fragment.width()
    @lineHeight = fragment.outerHeight()
    fragment.remove()

  scrollBottom: (newValue) ->
    if newValue?
      @scrollTop(newValue - @height())
    else
      @scrollTop() + @height()

  scrollRight: (newValue) ->
    if newValue?
      @scrollLeft(newValue - @width())
    else
      @scrollLeft() + @width()

  getCursor: -> @cursor
  getSelection: -> @selection

  getCurrentLine: -> @buffer.getLine(@getCursorRow())
  getSelectedText: -> @selection.getText()
  moveCursorUp: -> @cursor.moveUp()
  moveCursorDown: -> @cursor.moveDown()
  moveCursorRight: -> @cursor.moveRight()
  moveCursorLeft: -> @cursor.moveLeft()
  setCursorPosition: (point) -> @cursor.setPosition(point)
  getCursorPosition: -> @cursor.getPosition()
  setCursorRow: (row) -> @cursor.setRow(row)
  getCursorRow: -> @cursor.getRow()
  setCursorColumn: (column) -> @cursor.setColumn(column)
  getCursorColumn: -> @cursor.getColumn()

  selectRight: -> @selection.selectRight()
  selectLeft: -> @selection.selectLeft()
  selectUp: -> @selection.selectUp()
  selectDown: -> @selection.selectDown()
  selectToPosition: (position) ->
    @selection.selectToPosition(position)

  insertText: (text) -> @selection.insertText(text)
  insertNewline: -> @selection.insertNewline()

  cutSelection: -> @selection.cut()
  copySelection: -> @selection.copy()
  paste: -> @selection.insertText(atom.native.readFromPasteboard())

  backspace: ->
    @selectLeft() if @selection.isEmpty()
    @selection.delete()

  delete: ->
    @selectRight() if @selection.isEmpty()
    @selection.delete()

