import "package:angular2/di.dart" show Injectable;
import "package:angular2/src/platform/dom/dom_adapter.dart" show DOM;

import "event_manager.dart" show EventManagerPlugin;

@Injectable()
class DomEventsPlugin extends EventManagerPlugin {
  // This plugin should come last in the list of plugins, because it accepts all

  // events.
  bool supports(String eventName) {
    return true;
  }

  Function addEventListener(
      dynamic element, String eventName, Function handler) {
    var zone = this.manager.getZone();
    var outsideHandler = (event) => zone.runGuarded(() => handler(event));
    return this.manager.getZone().runOutsideAngular(
        () => DOM.onAndCancel(element, eventName, outsideHandler));
  }
}
