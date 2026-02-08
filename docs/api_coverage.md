# API coverages
- Puppeteer version: v24.37.0
- puppeteer-ruby version: 0.50.0

## Puppeteer

* connect
* defaultArgs => `#default_args`
* executablePath => `#executable_path`
* launch
* ~~puppeteer~~

## ~~Accessibility~~

* ~~snapshot~~

## Browser

* ~~addScreen~~
* browserContexts => `#browser_contexts`
* close
* ~~cookies~~
* createBrowserContext => `#create_browser_context`
* defaultBrowserContext => `#default_browser_context`
* ~~deleteCookie~~
* ~~deleteMatchingCookies~~
* disconnect
* ~~getWindowBounds~~
* ~~installExtension~~
* isConnected => `#connected?`
* newPage => `#new_page`
* pages
* process
* ~~removeScreen~~
* ~~screens~~
* ~~setCookie~~
* setPermission => `#set_permission`
* ~~setWindowBounds~~
* target
* targets
* ~~uninstallExtension~~
* userAgent => `#user_agent`
* version
* waitForTarget => `#wait_for_target`
* wsEndpoint => `#ws_endpoint`

## BrowserContext

* browser
* clearPermissionOverrides => `#clear_permission_overrides`
* close
* cookies
* deleteCookie => `#delete_cookie`
* deleteMatchingCookies => `#delete_matching_cookies`
* newPage => `#new_page`
* overridePermissions => `#override_permissions`
* pages
* setCookie => `#set_cookie`
* setPermission => `#set_permission`
* targets
* waitForTarget => `#wait_for_target`

## ~~BrowserLauncher~~

* ~~defaultArgs~~
* ~~executablePath~~
* ~~launch~~

## CDPSession

* connection
* detach
* id
* send

## Connection

* createSession => `#create_session`
* dispose
* ~~fromSession~~
* send
* session
* url

## ~~ConnectionClosedError~~


## ConsoleMessage

* args
* location
* stackTrace => `#stack_trace`
* text
* ~~type~~

## Coverage

* startCSSCoverage => `#start_css_coverage`
* startJSCoverage => `#start_js_coverage`
* stopCSSCoverage => `#stop_css_coverage`
* stopJSCoverage => `#stop_js_coverage`

## CSSCoverage

* start
* stop

## ~~DeviceRequestPrompt~~

* ~~cancel~~
* ~~select~~
* ~~waitForDevice~~

## Dialog

* accept
* defaultValue => `#default_value`
* dismiss
* message
* type

## ElementHandle

* $ => `#query_selector`
* $$ => `#query_selector_all`
* $$eval => `#eval_on_selector_all`
* $eval => `#eval_on_selector`
* asLocator => `#as_locator`
* ~~autofill~~
* ~~backendNodeId~~
* boundingBox => `#bounding_box`
* boxModel => `#box_model`
* click
* clickablePoint => `#clickable_point`
* contentFrame => `#content_frame`
* drag
* dragAndDrop => `#drag_and_drop`
* dragEnter => `#drag_enter`
* dragOver => `#drag_over`
* drop
* focus
* hover
* isHidden => `#hidden?`
* isIntersectingViewport => `#intersecting_viewport?`
* isVisible => `#visible?`
* press
* screenshot
* ~~scrollIntoView~~
* select
* tap
* toElement => `#to_element`
* touchEnd => `#touch_end`
* touchMove => `#touch_move`
* touchStart => `#touch_start`
* type => `#type_text`
* uploadFile => `#upload_file`
* waitForSelector => `#wait_for_selector`

## ~~EventEmitter~~

* ~~emit~~
* ~~listenerCount~~
* ~~off~~
* ~~on~~
* ~~once~~
* ~~removeAllListeners~~

## ~~ExtensionTransport~~

* ~~close~~
* ~~connectTab~~
* ~~send~~

## FileChooser

* accept
* cancel
* isMultiple => `#multiple?`

## Frame

* $ => `#query_selector`
* $$ => `#query_selector_all`
* $$eval => `#eval_on_selector_all`
* $eval => `#eval_on_selector`
* addScriptTag => `#add_script_tag`
* addStyleTag => `#add_style_tag`
* childFrames => `#child_frames`
* click
* content
* evaluate
* evaluateHandle => `#evaluate_handle`
* focus
* frameElement => `#frame_element`
* goto
* hover
* isDetached => `#detached?`
* locator
* name
* page
* parentFrame => `#parent_frame`
* select
* setContent => `#set_content`
* tap
* title
* type => `#type_text`
* url
* waitForFunction => `#wait_for_function`
* waitForNavigation => `#wait_for_navigation`
* waitForSelector => `#wait_for_selector`

## HTTPRequest

* abort
* abortErrorReason => `#abort_error_reason`
* continue
* continueRequestOverrides => `#continue_request_overrides`
* enqueueInterceptAction => `#enqueue_intercept_action`
* failure
* fetchPostData => `#fetch_post_data`
* finalizeInterceptions => `#finalize_interceptions`
* frame
* ~~hasPostData~~
* headers
* initiator
* interceptResolutionState => `#intercept_resolution_state`
* isInterceptResolutionHandled => `#intercept_resolution_handled?`
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
* ~~content~~
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
* timing
* url

## JSCoverage

* start
* stop

## JSHandle

* asElement => `#as_element`
* dispose
* evaluate
* evaluateHandle => `#evaluate_handle`
* getProperties => `#properties`
* getProperty => `#[]`
* jsonValue => `#json_value`
* remoteObject => `#remote_object`
* toString => `#to_s`

## Keyboard

* down
* press
* sendCharacter => `#send_character`
* type => `#type_text`
* up

## Locator

* click
* clone
* fill
* filter
* hover
* map
* ~~race~~
* scroll
* setEnsureElementIsInTheViewport => `#set_ensure_element_is_in_the_viewport`
* setTimeout => `#set_timeout`
* setVisibility => `#set_visibility`
* setWaitForEnabled => `#set_wait_for_enabled`
* setWaitForStableBoundingBox => `#set_wait_for_stable_bounding_box`
* wait
* waitHandle => `#wait_handle`

## Mouse

* click
* down
* drag
* dragAndDrop => `#drag_and_drop`
* dragEnter => `#drag_enter`
* dragOver => `#drag_over`
* drop
* move
* reset
* up
* wheel

## Page

* $ => `#query_selector`
* $$ => `#query_selector_all`
* $$eval => `#eval_on_selector_all`
* $eval => `#eval_on_selector`
* addScriptTag => `#add_script_tag`
* addStyleTag => `#add_style_tag`
* authenticate
* bringToFront => `#bring_to_front`
* browser
* browserContext => `#browser_context`
* captureHeapSnapshot => `#capture_heap_snapshot`
* click
* close
* content
* cookies
* ~~createCDPSession~~
* createPDFStream => `#create_pdf_stream`
* deleteCookie => `#delete_cookie`
* emulate
* emulateCPUThrottling => `#emulate_cpu_throttling`
* ~~emulateFocusedPage~~
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
* ~~getDefaultNavigationTimeout~~
* getDefaultTimeout => `#default_timeout`
* goBack => `#go_back`
* goForward => `#go_forward`
* goto
* hover
* isClosed => `#closed?`
* isDragInterceptionEnabled => `#drag_interception_enabled?`
* isJavaScriptEnabled => `#javascript_enabled?`
* isServiceWorkerBypassed => `#service_worker_bypassed?`
* locator
* mainFrame => `#main_frame`
* metrics
* ~~openDevTools~~
* pdf
* queryObjects => `#query_objects`
* reload
* removeExposedFunction => `#remove_exposed_function`
* removeScriptToEvaluateOnNewDocument => `#remove_script_to_evaluate_on_new_document`
* ~~resize~~
* ~~screencast~~
* screenshot
* select
* setBypassCSP => `#bypass_csp=`
* ~~setBypassServiceWorker~~
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
* type => `#type_text`
* url
* viewport
* ~~waitForDevicePrompt~~
* waitForFileChooser => `#wait_for_file_chooser`
* waitForFrame => `#wait_for_frame`
* waitForFunction => `#wait_for_function`
* waitForNavigation => `#wait_for_navigation`
* waitForNetworkIdle => `#wait_for_network_idle`
* waitForRequest => `#wait_for_request`
* waitForResponse => `#wait_for_response`
* waitForSelector => `#wait_for_selector`
* ~~windowId~~
* workers

## ~~ProtocolError~~


## ~~ScreenRecorder~~

* ~~stop~~

## ~~SecurityDetails~~

* ~~issuer~~
* ~~protocol~~
* ~~subjectAlternativeNames~~
* ~~subjectName~~
* ~~validFrom~~
* ~~validTo~~

## Target

* ~~asPage~~
* browser
* browserContext => `#browser_context`
* createCDPSession => `#create_cdp_session`
* opener
* page
* type
* url
* worker

## TimeoutError


## TouchError


## Touchscreen

* tap
* touchEnd => `#touch_end`
* touchMove => `#touch_move`
* touchStart => `#touch_start`

## Tracing

* start
* stop

## ~~UnsupportedOperation~~


## WebWorker

* close
* evaluate
* evaluateHandle => `#evaluate_handle`
* url
