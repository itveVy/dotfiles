{Emitter, Disposable, CompositeDisposable} = require 'atom'
{registerElement} = require './utils'

class SearchInput extends HTMLElement
  literalModeDeactivator: null

  onDidChange: (fn) -> @emitter.on 'did-change', fn
  onDidConfirm: (fn) -> @emitter.on 'did-confirm', fn
  onDidCancel: (fn) -> @emitter.on 'did-cancel', fn
  onDidUnfocus: (fn) -> @emitter.on 'did-unfocus', fn
  onDidCommand: (fn) -> @emitter.on 'did-command', fn

  createdCallback: ->
    @className = "vim-mode-plus-search-container"
    @emitter = new Emitter

    @innerHTML = """
    <div class='options-container'>
      <span class='inline-block-tight btn btn-primary'>.*</span>
    </div>
    <div class='editor-container'>
      <atom-text-editor mini class='editor vim-mode-plus-search'></atom-text-editor>
    </div>
    """
    [optionsContainer, editorContainer] = @getElementsByTagName('div')
    @regexSearchStatus = optionsContainer.firstElementChild
    @editorElement = editorContainer.firstElementChild
    @editor = @editorElement.getModel()
    @editor.setMini(true)

    @editor.onDidChange =>
      return if @finished
      @emitter.emit('did-change', @editor.getText())

    @panel = atom.workspace.addBottomPanel(item: this, visible: false)
    this

  destroy: ->
    @disposables.dispose()
    @editor.destroy()
    @panel?.destroy()
    {@editor, @panel, @editorElement, @vimState} = {}
    @remove()

  handleEvents: ->
    atom.commands.add @editorElement,
      'core:confirm': => @confirm()
      'core:cancel': => @cancel()
      'blur': => @cancel() unless @finished
      'vim-mode-plus:input-cancel': => @cancel()

  focus: (@options={}) ->
    @finished = false

    @editorElement.classList.add('backwards') if @options.backwards
    @panel.show()
    @editorElement.focus()
    @commandSubscriptions = @handleEvents()

    # Cancel on tab switch
    disposable = atom.workspace.onDidChangeActivePaneItem =>
      disposable.dispose()
      @cancel() unless @finished

  unfocus: ->
    @editorElement.classList.remove('backwards')
    @regexSearchStatus.classList.add 'btn-primary'
    @literalModeDeactivator?.dispose()

    @commandSubscriptions?.dispose()
    @finished = true
    atom.workspace.getActivePane().activate()
    @editor.setText ''
    @panel?.hide()
    @emitter.emit('did-unfocus')

  updateOptionSettings: ({useRegexp}={}) ->
    @regexSearchStatus.classList.toggle('btn-primary', useRegexp)

  setCursorWord: ->
    @editor.insertText(@vimState.editor.getWordUnderCursor())

  activateLiteralMode: ->
    if @literalModeDeactivator?
      @literalModeDeactivator.dispose()
    else
      @literalModeDeactivator = new CompositeDisposable()
      @editorElement.classList.add('literal-mode')

      @literalModeDeactivator.add new Disposable =>
        @editorElement.classList.remove('literal-mode')
        @literalModeDeactivator = null

  isVisible: ->
    @panel?.isVisible()

  cancel: ->
    @emitter.emit('did-cancel')
    @unfocus()

  confirm: (landingPoint=null) ->
    @emitter.emit('did-confirm', {input: @editor.getText(), landingPoint})
    @unfocus()

  stopPropagation: (oldCommands) ->
    newCommands = {}
    for name, fn of oldCommands
      do (fn) ->
        if ':' in name
          commandName = name
        else
          commandName = "vim-mode-plus:#{name}"
        newCommands[commandName] = (event) ->
          event.stopImmediatePropagation()
          fn(event)
    newCommands

  initialize: (@vimState) ->
    @vimState.onDidFailToSetTarget =>
      @cancel()

    @disposables = new CompositeDisposable
    @disposables.add @vimState.onDidDestroy(@destroy.bind(this))

    @registerCommands()
    this

  registerCommands: ->
    atom.commands.add @editorElement, @stopPropagation(
      "search-confirm": => @confirm()
      "search-land-to-start": => @confirm()
      "search-land-to-end": => @confirm('end')
      "search-cancel": => @cancel()

      "search-visit-next": => @emitter.emit('did-command', name: 'visit', direction: 'next')
      "search-visit-prev": => @emitter.emit('did-command', name: 'visit', direction: 'prev')

      "select-occurrence-from-search": => @emitter.emit('did-command', name: 'occurrence', operation: 'SelectOccurrence')
      "change-occurrence-from-search": => @emitter.emit('did-command', name: 'occurrence', operation: 'ChangeOccurrence')
      "add-occurrence-pattern-from-search": => @emitter.emit('did-command', name: 'occurrence')

      "search-insert-wild-pattern": => @editor.insertText('.*?')
      "search-activate-literal-mode": => @activateLiteralMode()
      "search-set-cursor-word": => @setCursorWord()
      'core:move-up': => @editor.setText @vimState.searchHistory.get('prev')
      'core:move-down': => @editor.setText @vimState.searchHistory.get('next')
    )

SearchInputElement = registerElement 'vim-mode-plus-search-input',
  prototype: SearchInput.prototype

module.exports = {
  SearchInputElement
}
