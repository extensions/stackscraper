`// ==UserScript==
// @name           StackScraper
// @version        0.0.1
// @namespace      http://extensions.github.com/stackscraper/
// @description    Allows 10k users to export deleted questions as JSON. Maybe other things too.
// @include        http://*.stackexchange.com/*
// @include        http://stackoverflow.com/*
// @include        http://*.stackoverflow.com/*
// @include        http://superuser.com/*
// @include        http://*.superuser.com/*
// @include        http://serverfault.com/*
// @include        http://*.serverfault.com/*
// @include        http://stackapps.com/*
// @include        http://*.stackapps.com/*
// @include        http://askubuntu.com/*
// @include        http://*.askubuntu.com/*
// @include        http://answers.onstartups.com/*
// @include        http://*.answers.onstartups.com/*
// ==/UserScript==
`
# jQuerys are suffixied with $, Promises suffixed with P

BlobBuilder = @BlobBuilder or @WebKitBlobBuilder or @MozBlobBuilder or @OBlobBuilder
URL = @URL or @webkitURL or @mozURL or @oURL

makeThrottle = (interval) ->
  # Creates a throttle with a given interval. the throttle takes a function and wraps it such that it yields
  # deferred results and the wrapped function won't be called more often than once every interval miliseconds.
  queue = []
  intervalId = null
  throttle = (f) ->
    throttled = ->
      thisVal = this
      argVals = arguments
      resultP = new $.Deferred
      
      if intervalId?
        queue.push [f, thisVal, argVals, resultP]
      else
        $.when(f.apply thisVal, argVals).then(resultP.resolve, resultP.reject, resultP.notify)
        intervalId = setInterval ->
          if queue.length
            [f_, thisVal_, argVals_, resultP_] = queue.shift()
            $.when(f_.apply thisVal_, argVals_).then(resultP_.resolve, resultP_.reject, resultP_.notify)
          else
            clearInterval intervalId
            intervalId = null
        , interval
      
      resultP

makeDocument = (html, title = '') ->
  doc = document.implementation.createHTMLDocument(title)
  if html? then doc.head.parentElement.innerHTML = html
  doc

class StackScraper
  constructor: ->
    @posts = {}
  
  getQuestion: (questionid) ->
    @getShallowQuestion(questionid).pipe (shallowQuestion) ->
      shallowQuestion
  
  getShallowQuestion: (questionid) ->
    @getQuestionDocuments(questionid).pipe (pages) ->
      question = scrapePostElement($('.question', pages[0]))
      question.title = $('#question-header h1 a', pages[0]).text()
      question.link = $('#question-header h1 a', pages[0]).attr('href')
      question.tags = $(tag).text() for tag in $('.post-taglist .post-tag', pages[0])
      question.favorite_count = +($('.favoritecount', pages[0]).text() ? 0)
      question.answers = []
      
      for page$ in pages
        for answer in page$
          question.answers.push scrapePostElement answer
      
      question
  
  getQuestionDocuments: (questionid) ->
    @ajax("/questions/#{questionid}").pipe (firstSource) ->
      firstPage$ = $(makeDocument(firstSource))
      
      # if there are multiple pages, request 'em all.
      if lastPageNav$ = $(".page-numbers:not(.next)").last()
        pageCount = +lastPage$.text()
        
        $.when(firstPage$, (for pageNumber in [2..pageCount]
          @ajax("/questions/#{quesetionid}?page#{pageNumber}").pipe (source) ->
            $(makeDocument(source))
        )...).pipe (pages...) -> pages
      else
        [firstPage$]
  
  scrapePostElement = (post$) ->
    if is_question = post$.is('.question')
      post =
        post_id: +post$.data('questionid')
        post_type: 'question'
        is_accepted: post$.find('.vote-accepted-on').length isnt 0
    else
      post =
        post_id: +post$.data('questionid')
        post_type: 'answer'
      
    post.body = $.trim post$.find('.post-text').html()
    post.score = +post$.find('.vote-count-post').text()
    post.deleted = post$.is('.deleted-question, .deleted-answer')
      
    sigs = post$.find('.post-signature')
    if sigs.length is 2
      [editorSig, ownerSig] = sigs
    else
      editorSig = null
      [ownerSig] = sigs
      
    if communityOwnage$ = post$.find('.community-wiki')
      post.community_owned_date_s = communityOwnage$.attr('title').match(/As of ([^\.])./)[1]
    else
      if ownerSig? and not communityOwnage$
        post.owner =
          user_id: +$('.user-details a', ownerSig).split(/\//g)[2]
          display_name: $('.user-details a', ownerSig).text()
          reputation: $('.reputation-score', ownerSig).text().replace(/,/g, '')
          profile_image: $('.user-gravatar32 img').attr('src')
        
      if editorSig? and not communityOwnage$
        post.last_editor =
          user_id: +$('.user-details a', editorSig).split(/\//g)[2]
          display_name: $('.user-details a', editorSig).text()
          reputation: $('.reputation-score', editorSig).text().replace(/,/g, '')
          profile_image: $('.user-gravatar32 img').attr('src')
      
    if editorSig? and editTime$ = $('.relativetime', editorSig)
      post.last_edit_date_s = editTime$.text()
      post.last_edit_date_z = editTime$.attr('title')
      
    if ownerSig? and creationTime$ = $('.relativetime', ownerSig)
      post.creation_date_s = ownerSig$.text()
      post.creation_date_z = ownerSig$.attr('title')
    
      post
  
  # be nice: wrap $.ajax to add our throttle and header.
  ajax: (makeThrottle 500) (url, options = {}) ->   
    existingBeforeSend = options.beforeSend;
    options.beforeSend = (request) ->
      request.setRequestHeader 'X-StackScraper-Version', '0.0.1'
      return existingBeforeSend.apply this, arguments
    $.ajax(url, options)

scraper = new StackScraper
scraper.getShallowQuestion(12830).then (x) -> console.log(x)
