class Hypothesis extends Annotator
  events:
    serviceDiscovery: 'serviceDiscovery'

  # Plugin configuration
  options:
    Discovery: {}
    Heatmap: {}
    Progress: {}
    Permissions:
      ignoreToken: true
      permissions:
        read: ['group:__world__']
      userAuthorize: (action, annotation, user) ->
        if annotation.permissions
          tokens = annotation.permissions[action] || []

          if tokens.length == 0
            # Empty or missing tokens array: only admin can perform action.
            return false

          for token in tokens
            if this.userId(user) == token
              return true
            if token == 'group:__world__'
              return true
            if token == 'group:__authenticated__' and this.user?
              return true

          # No tokens matched: action should not be performed.
          return false

        # Coarse-grained authorization
        else if annotation.user
          return user and this.userId(user) == this.userId(annotation.user)

        # No authorization info on annotation: free-for-all!
        true
      showEditPermissionsCheckbox: false,
      showViewPermissionsCheckbox: false,
      userString: (user) -> user.replace(/^acct:(.+)@(.+)$/, '$1 on $2')
    Threading: {}

  # Internal state
  dragging: false     # * To enable dragging only when we really want to

  defineAsyncInitTasks: ->
    super

    # This task overrides an upstream task
    @init.createSubTask
      name: "viewer & editor"
      code: (task) =>
        # Here as a noop just to make the Permissions plugin happy
        # XXX: Change me when Annotator stops assuming things about viewers
        @viewer = 
          addField: (-> )
        task.ready()

    # This task overrides an upstream task
    @init.createDummySubTask name: "dynamic CSS style"

    $location = @element.injector().get '$location'
    $window = @element.injector().get '$window'
    $rootScope = @element.injector().get '$rootScope'
    drafts = @element.injector().get 'drafts'

    origin = $location.search().xdm

    # Create a task to set up the bridge plugin,
    # which bridges the main annotation methods
    # between the host page and the panel widget.
    # (Calling addPlugin will create an async task.)
    whitelist = ['diffHTML', 'quote', 'ranges', 'target', 'id']
    this.addPlugin 'Bridge',
      origin: origin
      window: $window.parent
      formatter: (annotation) =>
        formatted = {}
        for k, v of annotation when k in whitelist
          formatted[k] = v
        formatted
      parser: (annotation) =>
        parsed = {}
        for k, v of annotation when k in whitelist
          parsed[k] = v
        parsed

    @init.createSubTask
      name: "api channel"
      code: (task) =>
        @api = Channel.build
          origin: origin
          scope: 'annotator:api'
          window: $window.parent
          onReady: =>
            # Signal that the task is done    
            task.ready()

        .bind('addToken', (ctx, token) =>
          @element.scope().token = token
          @element.scope().$digest()
        )        

    @init.createSubTask
      name: "panel channel"
      code: (task) =>
        @provider = Channel.build
          origin: origin
          scope: 'annotator:panel'
          window: $window.parent
          onReady: =>
            # Signal that the task is done
            task.ready()

            # Dodge toolbars [DISABLE]
            #@provider.getMaxBottom (max) =>
            #  @element.css('margin-top', "#{max}px")
            #  @element.find('.topbar').css("top", "#{max}px")
            #  @element.find('#gutter').css("margin-top", "#{max}px")
            #  @plugins.Heatmap.BUCKET_THRESHOLD_PAD += max

         @provider
          .bind('publish', (ctx, args...) => this.publish args...)

          .bind('back', =>
            # This guy does stuff when you "back out" of the interface.
            # (Currently triggered by a click on the source page.)
            return unless drafts.discard()
            if $location.path() == '/viewer' and $location.search()?.id?
              $rootScope.$apply => $location.search('id', null).replace()
            else
              $rootScope.$apply => this.hide()
          )

          .bind('setLoggerStartTime', (ctx, timestamp) =>
            @log.trace "Setting logging start time."
#            window.XLoggerStartTime = timestamp
            @log.trace "Now we have consistent timing."
          )

          .bind('publishAnnotationsAnchored', (ctx) =>
            this.publish('annotationsAnchored')                
          )

          .bind('initDone', (ctx) =>
            @hostInit.dfd.ready()
          )
        
          .bind('initProgress', (ctx, status) =>
            delete status.task
            @hostInit.dfd.notify status
          ) 

    @init.createSubTask
      name: "href"
      deps: [
        "panel channel", # we are talking to @provider
        "discovery" # we need the store options from discovery
      ]
      code: (task) =>
        # Get the location of the annotated document
        @provider.call
          method: 'getHref'
          success: (href) =>
            options = angular.extend {}, (@options.Store or {}),
              annotationData:
                uri: href
              loadFromSearch:
                limit: 1000
                uri: href
              # We don't want to trigger a loading on plugin init
              noLoading: true

            @options.Store = options
            task.ready()

    @init.createSubTask
      name: "load store plugin"
      deps: ["href"] # we need the store options prepared with the right href
      code: (task) =>
        this.addPlugin 'Store', @options.Store
        this.patch_store this.plugins.Store
        task.ready()

    # Create a "shadow" task for the initial loading
    @firstLoad = @init.createSubTask
      name: "wait for load"
      code: ->

    # Create a "shadow" task for things happening on the host side
    @hostInit = @init.createSubTask
      weight: 50
      name: "host init"
      code: ->

    # Load plugins
    # (This will create the appropriate init tasks, too.)
    for own name, opts of @options
      if not @plugins[name] and name of Annotator.Plugin
        this.addPlugin(name, opts)
                
  this.$inject = ['$document', '$location', '$rootScope', '$route', 'drafts']
  constructor: ($document, $location, $rootScope, $route, drafts) ->

    window.wtfh = this
        
    # We are in an iframe, so the time registered there is invalid. Clearing it.
#    delete window.XLoggerStartTime
    @log ?= getXLogger "Hypothesis"
#    @log.setLevel XLOG_LEVEL.DEBUG
    @log.debug "Started constructor."


    super ($document.find 'body'),
      noScan: true
      noInit: true

#    @tasklog.setLevel XLOG_LEVEL.DEBUG

    this.initAsync() 

    # Add some info to new annotations
    this.subscribe 'beforeAnnotationCreated', (annotation) =>
      # Annotator assumes a valid array of targets and highlights.
      unless annotation.target?
        annotation.target = []
      unless annotation.highlights?
        annotation.highlights = []

      # Register it with the draft service
      drafts.add annotation

    # Set default owner permissions on all annotations
    for event in ['beforeAnnotationCreated', 'beforeAnnotationUpdated']
      this.subscribe event, (annotation) =>
        permissions = @plugins.Permissions
        if permissions.user?
          userId = permissions.options.userId(permissions.user)
          for action, roles of annotation.permissions
            unless userId in roles then roles.push userId

    # Update the heatmap when the host is updated or annotations are loaded
    bridge = @plugins.Bridge
    heatmap = @plugins.Heatmap
    progress = @plugins.Progress

    # Keep updating the progress bar with the status of the init task
    @init.progress (info) =>
      progress.updateProgress info.text, info.progress

    threading = @threading
    updateOn = [
      'hostUpdated'
      'annotationsLoaded'
      'annotationsAnchored'
      'annotationCreated'
      'annotationDeleted'
    ]
    for event in updateOn
      this.subscribe event, =>
        @provider.call
          method: 'getHighlights'
          success: ({highlights, offset}) ->
            heatmap.updateHeatmap
              highlights:
                for hl in highlights when hl.data
                  annotation = bridge.cache[hl.data]
                  angular.extend hl, data: annotation
              offset: offset

    # Reload the route after annotations are loaded
    this.subscribe 'annotationsLoaded', -> $route.reload()
    @log.debug "Finished constructor."

  getSynonymURLs: (href) ->
    stringStartsWith = (string, prefix) ->
      prefix is string.substr 0, prefix.length

    stringEndsWith = (string, suffix) ->
      suffix is string.substr string.length - suffix.length

    @log.debug "Looking for synonym URLs for '" + href + "'..."
    results = []
    if stringStartsWith href, "http://elife.elifesciences.org/content"
      if stringEndsWith href, ".full-text.pdf"
        root = href.substr 0, href.length - ".full-text.pdf".length
        results.push root
        results.push root + ".full.pdf"
      else if stringEndsWith href, ".full.pdf"
        root = href.substr 0, href.length - ".full.pdf".length
        results.push root
        results.push root + ".full-text.pdf"        
      else
        results.push href + ".full.pdf"
        results.push href + ".full-text.pdf"
    else if stringStartsWith href, "https://peerj.com/articles/"
      if stringEndsWith href, ".pdf"
        results.push (href.substr 0, href.length - 4) + "/"
      else
        results.push (href.substr 0, href.length - 1) + ".pdf"

#    results.push "fake uri"     
    return results

  _setupWrapper: ->
    @wrapper = @element.find('#wrapper')
    .on 'mousewheel', (event, delta) ->
      # prevent overscroll from scrolling host frame
      # This is actually a bit tricky. Starting from the event target and
      # working up the DOM tree, find an element which is scrollable
      # and has a scrollHeight larger than its clientHeight.
      # I've obsered that some styles, such as :before content, may increase
      # scrollHeight of non-scrollable elements, and that there a mysterious
      # discrepancy of 1px sometimes occurs that invalidates the equation
      # typically cited for determining when scrolling has reached bottom:
      #   (scrollHeight - scrollTop == clientHeight)
      $current = $(event.target)
      while $current.css('overflow') in ['hidden', 'visible']
        $parent = $current.parent()
        # Break out on document nodes
        if $parent.get(0).nodeType == 9
          event.preventDefault()
          return
        $current = $parent
      scrollTop = $current[0].scrollTop
      scrollEnd = $current[0].scrollHeight - $current[0].clientHeight
      if delta > 0 and scrollTop == 0
        event.preventDefault()
      else if delta < 0 and scrollEnd - scrollTop <= 5
        event.preventDefault()
    this

  _setupDocumentEvents: ->
    el = document.createElementNS 'http://www.w3.org/1999/xhtml', 'canvas'
    el.width = el.height = 1
    @element.append el

    handle = @element.find('.topbar .tri')[0]
    handle.addEventListener 'dragstart', (event) =>
      event.dataTransfer.setData 'text/plain', ''
      event.dataTransfer.setDragImage el, 0, 0
      @dragging = true
      @provider.notify method: 'setDrag', params: true      
      @provider.notify method: 'dragFrame', params: event.screenX
    handle.addEventListener 'dragend', (event) =>
      @dragging = false
      @provider.notify method: 'setDrag', params: false      
      @provider.notify method: 'dragFrame', params: event.screenX
    @element[0].addEventListener 'dragover', (event) =>
      if @dragging then @provider.notify method: 'dragFrame', params: event.screenX
    @element[0].addEventListener 'dragleave', (event) =>
      if @dragging then @provider.notify method: 'dragFrame', params: event.screenX

    this

  # Do nothing in the app frame, let the host handle it.
  setupAnnotation: (annotation) -> annotation

  showViewer: (annotations=[]) =>
    this.show()
    @element.injector().invoke [
      '$location', '$rootScope',
      ($location, $rootScope) ->
        $rootScope.annotations = annotations
        $location.path('/viewer').replace()
        $rootScope.$digest()
    ]
    this

  showEditor: (annotation) =>
    this.show()
    @element.injector().invoke [
      '$location', '$rootScope', '$route'
      ($location, $rootScope, $route) =>
        unless this.plugins.Auth? and this.plugins.Auth.haveValidToken()
          $route.current.locals.$scope.$apply ->
            $route.current.locals.$scope.$emit 'showAuth', true
          return

        # Set the path
        search =
          id: annotation.id
          action: 'create'
        $location.path('/editor').search(search)
 
        # Digest the change
        $rootScope.$digest()

        # Push the annotation into the editor scope
        if $route.current.controller is 'EditorController'
          $route.current.locals.$scope.$apply (s) -> s.annotation = annotation
    ]
    this

  show: =>
    @element.scope().frame.visible = true

  hide: =>
    @element.scope().frame.visible = false

  patch_store: (store) =>
    $location = @element.injector().get '$location'
    $rootScope = @element.injector().get '$rootScope'

    # When the store plugin finishes a request, update the annotation
    # using a monkey-patched update function which updates the threading
    # if the annotation has a newly-assigned id and ensures that the id
    # is enumerable.
    store.updateAnnotation = (annotation, data) =>
      if annotation.id? and annotation.id != data.id
        # Update the id table for the threading
        thread = @threading.getContainer annotation.id
        thread.id = data.id
        @threading.idTable[data.id] = thread
        delete @threading.idTable[annotation.id]

        # The id is no longer temporary and should be serialized
        # on future Store requests.
        Object.defineProperty annotation, 'id',
          configurable: true
          enumerable: true
          writable: true

        # If the annotation is loaded in a view, switch the view
        # to reference the new id.
        search = $location.search()
        if search? and search.id == annotation.id
          search.id = data.id
          $location.search(search).replace()

      # Update the annotation with the new data
      annotation = angular.extend annotation, data

      # Give angular a chance to react
      $rootScope.$digest()

  serviceDiscovery: (options) =>
    angular.extend @options, Store: options

class DraftProvider
  drafts: []

  $get: -> this
  add: (draft) -> @drafts.push draft unless this.contains draft
  remove: (draft) -> @drafts = (d for d in @drafts when d isnt draft)
  contains: (draft) -> (@drafts.indexOf draft) != -1

  discard: ->
    count = (d for d in @drafts when d.text?.length).length
    text =
      switch count
        when 0 then null
        when 1
          """You have an unsaved reply.

          Do you really want to discard this draft?"""
        else
          """You have #{count} unsaved replies.

          Do you really want to discard these drafts?"""

    if count == 0 or confirm text
      @drafts = []
      true
    else
      false


class FlashProvider
  queues:
    '': []
    info: []
    error: []
    success: []
  notice: null
  timeout: null

  constructor: ->
    # Configure notification classes
    angular.extend Annotator.Notification,
      INFO: 'info'
      ERROR: 'error'
      SUCCESS: 'success'

  _process: ->
    @timeout = null
    for q, msgs of @queues
      if msgs.length
        msg = msgs.shift()
        unless q then [q, msg] = msg
        notice = Annotator.showNotification msg, q
        @timeout = this._wait =>
          # work around Annotator.Notification not removing classes
          for _, klass of notice.options.classes
            notice.element.removeClass klass
          this._process()
        break

  $get: ['$timeout', 'annotator', ($timeout, annotator) ->
    this._wait = (cb) -> $timeout cb, 5000
    angular.bind this, this._flash
  ]

  _flash: (queue, messages) ->
    if @queues[queue]?
      @queues[queue] = @queues[queue]?.concat messages
      this._process() unless @timeout?


angular.module('h.services', [])
  .provider('drafts', DraftProvider)
  .provider('flash', FlashProvider)
  .service('annotator', Hypothesis)
