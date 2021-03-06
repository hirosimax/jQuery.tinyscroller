do ($ = jQuery, window = window, document = document) ->
  
  ns = {}
  $win = $(window)
  $doc = $(document)

  # we use math here
  
  round = Math.round
  min = Math.min
  abs = Math.abs


  # ============================================================
  # tiny utils
  
  # yOf

  ns.yOf = (el) ->
    y = 0
    while el.offsetParent
      y += el.offsetTop
      el = el.offsetParent
    y

  # isHash - is '#foobar' or not

  ns.isHash = (str) ->
    return /^#.+$/.test str

  # getWhereTo - find where to go

  ns.getWhereTo = (el) ->
    $el = $(el)
    ($el.data 'scrollto') or ($el.attr 'href')

  # calcY - caliculate Y of something

  ns.calcY = (target) ->

    # if target was number, do nothing
    if ($.type target) is 'number'
      return target

    # if target was string, try to find element
    if ($.type target) is 'string'

      # it must be hashval like '#foobar'
      if not ns.isHash target then return false

      # try to get y of the target
      $target = $doc.find target

    # else, it must be element
    else
      $target = $(target)

    if not $target.size() then return null
    y = ns.yOf $target[0]
    y

  # browser thing

  ns.scrollTop = ->
    $doc.scrollTop() or document.documentElement.scrollTop or document.body.scrollTop or window.pageYOffset or 0

  # browser detection

  ns.ua = do ->
    ret = {}
    ua = navigator.userAgent
    evalEach = (keys) ->
      matchesAny = false
      $.each keys, (i, current) ->
        expr = new RegExp current, 'i'
        if (Boolean ua.match(expr))
          ret[current] = true
          matchesAny = true
        else
          ret[current] = false
        true
      matchesAny
    if evalEach ['iphone', 'ipod', 'ipad'] or evalEach ['android']
      ret.mobile = true
    ret


  # ============================================================
  # event module

  class ns.Event

    bind: (ev, callback) ->
      @_callbacks = {} unless @_callbacks
      evs = ev.split(' ')
      for name in evs
        @_callbacks[name] or= []
        @_callbacks[name].push(callback)
      @

    one: (ev, callback) ->
      @_callbacks = {} unless @_callbacks
      @bind ev, ->
        @unbind(ev, arguments.callee)
        callback.apply(@, arguments)

    trigger: (args...) ->
      @_callbacks = {} unless @_callbacks
      ev = args.shift()
      list = @_callbacks?[ev]
      return unless list
      for callback in list
        if callback.apply(@, args) is false
          break
      @

    unbind: (ev, callback) ->
      @_callbacks = {} unless @_callbacks
      unless ev
        @_callbacks = {}
        return @

      list = @_callbacks?[ev]
      return this unless list

      unless callback
        delete @_callbacks[ev]
        return this

      for cb, i in list when cb is callback
        list = list.slice()
        list.splice(i, 1)
        @_callbacks[ev] = list
        break
      @


  # ============================================================
  # Scroller

  class ns.Scroller extends ns.Event

    eventNames = [
      'scrollstart'
      'scrollend'
      'scrollcancel'
    ]
    
    options:

      speed : 30 # scrollstep interval
      maxStep: 2000 # max distance(px) per scrollstep
      slowdownRate: 3 # something to define slowdown rate
      changehash: true # change hash after scrolling or not
      userskip: true # skip all scrolling steps if user scrolled manually while scrolling
      selector: 'a[href^=#]:not(.apply-noscroll)' # selector for delegation event binding
      adjustEndY: false
      dontAdjustEndYIfSelectorIs: null
      dontAdjustEndYIfYis: null

    constructor: (options) ->
      if options then @option options
      @_handleMobile()

    _handleMobile: ->
      # iOS's scrollTop is pretty different from desktop browsers.
      # This feature must be false
      if not ns.ua.mobile then return @
      @options.userskip = false
      @

    _invokeScroll: ->
      @trigger 'scrollstart', @_endY, @_reservedHash
      @_scrollDefer.then =>
        if @options.changehash and @_reservedHash
          location.hash = @_reservedHash
        @trigger 'scrollend', @_endY, @_reservedHash
      , =>
        @trigger 'scrollcancel', @_endY, @_reservedHash
      .always =>
        if @_reservedHash
          @_reservedHash = null
        @_scrollDefer = null
      @_stepToNext()
      @

    _stepToNext: =>
      
      top = ns.scrollTop() # current scrollposition
      o = @options

      # if @_prevY and top were not same, it must the user scrolled manually.
      # in such case, skip all scrolling immediately.
      if o.userskip and @_prevY and (top isnt @_prevY)
        window.scrollTo 0, @_endY
        @_scrollDefer?.resolve()
        @_prevY = null
        return @

      # the end point is below the winow
      if @_endY > top

        docH = $doc.height()
        winH = $win.height()

        # try to calc how long the next scrolling go here.
        # this is pretty complicated but is necessary to make it smooth.
        # calc planA and planB, then choose shorter distance.
        planA = round( (docH-top-winH) / o.slowdownRate )
        planB = round( (@_endY-top) / o.slowdownRate )
        endDistance = min(planA, planB)

        # if the distance was too long. normalize it with maxStep
        offset = min( endDistance, o.maxStep )

        # need to move at least 2px
        if offset < 2 then offset = 2

      # the end point is above the winow
      else
        offset = - min(abs(round((@_endY-top) / o.slowdownRate)), o.maxStep)

      # do scroll
      nextY = top + offset
      window.scrollTo 0, nextY
      @_prevY = nextY

      # if cancel was reserved, stop this
      if @_cancelNext
        @_cancelNext = false
        @_scrollDefer?.reject()
        return @

      # need zero timeout becaue Safari ignored changed window.scrollTo
      # value immediately. Oh my!
      setTimeout =>
        # check whether the scrolling was done or not
        if (abs(top - @_endY) <= 1) or (ns.scrollTop() is top)
          window.scrollTo 0, @_endY
          @_prevY = null
          @_scrollDefer?.resolve()
          return @
        # else, keep going
        @_stepToNext()
      , o.speed

      @

    scrollTo: (target, localOptions) ->

      handleAdjustendy = true

      # check options whether this scrolling handles adjustEndY or not
      if @options.changehash
        handleAdjustendy = false
      if @options.adjustEndY is false
        handleAdjustendy = false
      if localOptions?.adjustEndY is false
        handleAdjustendy = false

      if ns.isHash target
        @_reservedHash = target # reserve hash

        # ignore adjustY if it matches option
        if @options.dontAdjustEndYIfSelectorIs
          if $doc.find(target).is(@options.dontAdjustEndYIfSelectorIs)
            handleAdjustendy = false

      # try to calc endY
      endY = ns.calcY target
      return this if endY is false

      # handle dontAdjustEndYIfYis option
      if ($.type @options.dontAdjustEndYIfYis) is 'number'
        if endY is @options.dontAdjustEndYIfYis
          handleAdjustendy = false

      if localOptions?.adjustEndY?
        endY += localOptions.adjustEndY
      else
        if @options.adjustEndY isnt false
          endY += @options.adjustEndY

      @_endY = endY

      # this defer tells scroll end
      @_scrollDefer = $.Deferred()

      # start!
      @_invokeScroll()

      # we need deferred to know scrollend
      @_scrollDefer


    stop: ->
      # stop can't stop the scorlling immediately.
      # reserve to stop next one.
      $.Deferred (defer) =>
        if @_scrollDefer
          @_cancelNext = true
          @_scrollDefer.fail ->
            defer.resolve()
        else
          defer.resolve()

    option: (options) ->
      if not options then return @options
      @options = $.extend {}, @options, options
      @_handleMobile()
      
      $.each eventNames, (i, eventName) =>
        if @options[eventName]
          @bind eventName, @options[eventName]
        true
      @

    live: (selector) ->
      selector = selector or @options.selector
      self = @
      $doc.delegate selector, 'click', (e) ->
        e.preventDefault()
        self.scrollTo (ns.getWhereTo @)
      @


  # ============================================================
  # jQuery bridges

  $.fn.tinyscrollable = (options) ->
    scroller = new ns.Scroller options
    @each ->
      $el = $(@)
      $el.data 'tinyscroller', scroller
      if $el.data 'tinyscrollerattached' then return @
      $el.bind 'click', (e) ->
        e.preventDefault()
        scroller.scrollTo (ns.getWhereTo @)
      $el.data 'tinyscrollerattached', true


  # ============================================================
  
  # globalify
  
  $.TinyscrollerNs = ns
  $.Tinyscroller = ns.Scroller
