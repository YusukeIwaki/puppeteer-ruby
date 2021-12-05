# API coverages
- Puppeteer version: v12.0.0
- puppeteer-ruby version: 0.37.4

## Puppeteer

* ~~clearCustomQueryHandlers~~
* connect
* ~~createBrowserFetcher~~
* ~~customQueryHandlerNames~~
* defaultArgs => `#default_args`
* devices
* ~~errors~~
* executablePath => `#executable_path`
* launch
* networkConditions => `#network_conditions`
* product
* ~~registerCustomQueryHandler~~
* ~~unregisterCustomQueryHandler~~

## ~~BrowserFetcher~~

* ~~canDownload~~
* ~~download~~
* ~~host~~
* ~~localRevisions~~
* ~~platform~~
* ~~product~~
* ~~remove~~
* ~~revisionInfo~~

## Browser

* browserContexts => `#browser_contexts`
* close
* createIncognitoBrowserContext => `#create_incognito_browser_context`
* defaultBrowserContext => `#default_browser_context`
* disconnect
* isConnected => `#connected?`
* newPage => `#new_page`
* pages
* process
* target
* targets
* userAgent => `#user_agent`
* version
* waitForTarget => `#wait_for_target`
* wsEndpoint => `#ws_endpoint`

## BrowserContext

* browser
* clearPermissionOverrides => `#clear_permission_overrides`
* close
* isIncognito => `#incognito?`
* newPage => `#new_page`
* overridePermissions => `#override_permissions`
* pages
* targets
* waitForTarget => `#wait_for_target`

## Page

* $ => `#query_selector`
* $$ => `#query_selector_all`
* $$eval => `#eval_on_selector_all`
* $eval => `#eval_on_selector`
* $x => `#Sx`
* accessibility
* addScriptTag => `#add_script_tag`
* addStyleTag => `#add_style_tag`
* authenticate
* bringToFront => `#bring_to_front`
* browser
* browserContext => `#browser_context`
* click
* close
* content
* cookies
* coverage
* createPDFStream => `#create_pdf_stream`
* deleteCookie => `#delete_cookie`
* emulate
* emulateCPUThrottling => `#emulate_cpu_throttling`
* emulateIdleState => `#emulate_idle_state`
* emulateMediaFeatures => `#emulate_media_features`
* emulateMediaType => `#emulate_media_type`
* emulateNetworkConditions => `#emulate_network_conditions`
* emulateTimezone => `#emulate_timezone`
* emulateVisionDeficiency => `#emulate_vision_deficiency`
* evaluate
* evaluateHandle => `#evaluate_handle`
* evaluateOnNewDocument => `#evaluate_on_new_document`
* exposeFunction => `#expose_function`
* focus
* frames
* goBack => `#go_back`
* goForward => `#go_forward`
* goto
* hover
* isClosed => `#closed?`
* isDragInterceptionEnabled => `#drag_interception_enabled?`
* isJavaScriptEnabled => `#javascript_enabled?`
* keyboard
* mainFrame => `#main_frame`
* metrics
* mouse
* pdf
* queryObjects => `#query_objects`
* reload
* screenshot
* select
* setBypassCSP => `#bypass_csp=`
* setCacheEnabled => `#cache_enabled=`
* setContent => `#content=`
* setCookie => `#set_cookie`
* setDefaultNavigationTimeout => `#default_navigation_timeout=`
* setDefaultTimeout => `#default_timeout=`
* ~~setDragInterception~~
* setExtraHTTPHeaders => `#extra_http_headers=`
* setGeolocation => `#geolocation=`
* setJavaScriptEnabled => `#javascript_enabled=`
* setOfflineMode => `#offline_mode=`
* setRequestInterception => `#request_interception=`
* setUserAgent => `#user_agent=`
* setViewport => `#viewport=`
* tap
* target
* title
* ~~touchscreen~~
* tracing
* type => `#type_text`
* url
* viewport
* ~~waitFor~~
* waitForFileChooser => `#wait_for_file_chooser`
* ~~waitForFrame~~
* waitForFunction => `#wait_for_function`
* waitForNavigation => `#wait_for_navigation`
* ~~waitForNetworkIdle~~
* waitForRequest => `#wait_for_request`
* waitForResponse => `#wait_for_response`
* waitForSelector => `#wait_for_selector`
* waitForTimeout => `#wait_for_timeout`
* waitForXPath => `#wait_for_xpath`
* workers

## ~~WebWorker~~

* ~~evaluate~~
* ~~evaluateHandle~~
* ~~executionContext~~
* ~~url~~

## ~~Accessibility~~

* ~~snapshot~~

## Keyboard

* down
* press
* sendCharacter => `#send_character`
* type => `#type_text`
* up

## Mouse

* click
* down
* drag
* dragAndDrop => `#drag_and_drop`
* dragEnter => `#drag_enter`
* dragOver => `#drag_over`
* drop
* move
* up
* wheel

## ~~Touchscreen~~

* ~~tap~~

## Tracing

* start
* stop

## FileChooser

* accept
* cancel
* isMultiple => `#multiple?`

## Dialog

* accept
* defaultValue => `#default_value`
* dismiss
* message
* type

## ConsoleMessage

* args
* location
* ~~stackTrace~~
* text
* ~~type~~

## Frame

* $ => `#query_selector`
* $$ => `#query_selector_all`
* $$eval => `#eval_on_selector_all`
* $eval => `#eval_on_selector`
* $x => `#Sx`
* addScriptTag => `#add_script_tag`
* addStyleTag => `#add_style_tag`
* childFrames => `#child_frames`
* click
* content
* evaluate
* evaluateHandle => `#evaluate_handle`
* executionContext => `#execution_context`
* focus
* goto
* hover
* isDetached => `#detached?`
* ~~isOOPFrame~~
* name
* parentFrame => `#parent_frame`
* select
* setContent => `#set_content`
* tap
* title
* type => `#type_text`
* url
* ~~waitFor~~
* waitForFunction => `#wait_for_function`
* waitForNavigation => `#wait_for_navigation`
* waitForSelector => `#wait_for_selector`
* waitForTimeout => `#wait_for_timeout`
* waitForXPath => `#wait_for_xpath`

## ExecutionContext

* evaluate
* evaluateHandle => `#evaluate_handle`
* frame
* ~~queryObjects~~

## JSHandle

* asElement => `#as_element`
* dispose
* evaluate
* evaluateHandle => `#evaluate_handle`
* executionContext => `#execution_context`
* getProperties => `#properties`
* getProperty => `#[]`
* jsonValue => `#json_value`

## ElementHandle

* $ => `#query_selector`
* $$ => `#query_selector_all`
* $$eval => `#eval_on_selector_all`
* $eval => `#eval_on_selector`
* $x => `#Sx`
* asElement => `#as_element`
* boundingBox => `#bounding_box`
* boxModel => `#box_model`
* click
* clickablePoint => `#clickable_point`
* contentFrame => `#content_frame`
* dispose
* drag
* dragAndDrop => `#drag_and_drop`
* dragEnter => `#drag_enter`
* dragOver => `#drag_over`
* drop
* evaluate
* evaluateHandle => `#evaluate_handle`
* executionContext => `#execution_context`
* focus
* getProperties => `#properties`
* getProperty => `#[]`
* hover
* isIntersectingViewport => `#intersecting_viewport?`
* jsonValue => `#json_value`
* press
* screenshot
* select
* tap
* ~~toString~~
* type => `#type_text`
* uploadFile => `#upload_file`

## HTTPRequest

* abort
* abortErrorReason => `#abort_error_reason`
* continue
* continueRequestOverrides => `#continue_request_overrides`
* enqueueInterceptAction => `#enqueue_intercept_action`
* failure
* finalizeInterceptions => `#finalize_interceptions`
* frame
* headers
* ~~initiator~~
* isNavigationRequest => `#navigation_request?`
* method
* postData => `#post_data`
* redirectChain => `#redirect_chain`
* resourceType => `#resource_type`
* respond
* response
* responseForRequest => `#response_for_request`
* url

## HTTPResponse

* buffer
* frame
* ~~fromCache~~
* ~~fromServiceWorker~~
* headers
* json
* ~~ok~~
* remoteAddress => `#remote_address`
* request
* securityDetails => `#security_details`
* status
* statusText => `#status_text`
* text
* url

## ~~SecurityDetails~~

* ~~issuer~~
* ~~protocol~~
* ~~subjectAlternativeNames~~
* ~~subjectName~~
* ~~validFrom~~
* ~~validTo~~

## Target

* browser
* browserContext => `#browser_context`
* createCDPSession => `#create_cdp_session`
* opener
* page
* type
* url
* ~~worker~~

## CDPSession

* connection
* detach
* ~~id~~
* send

## Coverage

* startCSSCoverage => `#start_css_coverage`
* startJSCoverage => `#start_js_coverage`
* stopCSSCoverage => `#stop_css_coverage`
* stopJSCoverage => `#stop_js_coverage`

## TimeoutError


## ~~EventEmitter~~

* ~~addListener~~
* ~~emit~~
* ~~listenerCount~~
* ~~off~~
* ~~on~~
* ~~once~~
* ~~removeAllListeners~~
* ~~removeListener~~
