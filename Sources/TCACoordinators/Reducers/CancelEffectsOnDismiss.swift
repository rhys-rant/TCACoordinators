import ComposableArchitecture
import Foundation

/// Identifier for a particular route within a particular coordinator.
public struct CancellationIdentity<CoordinatorID: Hashable, RouteID: Hashable>: Hashable {
  let coordinatorId: CoordinatorID
  let routeId: RouteID
}

struct CancelEffectsOnDismiss<CoordinatorScreensReducer: ReducerProtocol, CoordinatorReducer: ReducerProtocol, CoordinatorID: Hashable, ScreenAction, RouteID: Hashable, C: Collection>: ReducerProtocol where CoordinatorScreensReducer.State == CoordinatorReducer.State, CoordinatorScreensReducer.Action == CoordinatorReducer.Action {
  let coordinatedScreensReducer: CoordinatorScreensReducer
  let routes: (CoordinatorReducer.State) -> C
  let routeAction: CasePath<Action, (RouteID, ScreenAction)>
  let cancellationId: CoordinatorID?
  let getIdentifier: (C.Element, C.Index) -> RouteID
  let coordinatorReducer: CoordinatorReducer

  var body: some ReducerProtocol<CoordinatorReducer.State, CoordinatorReducer.Action> {
    if let cancellationId {
      CancelTaggedRouteEffectsOnDismiss(
        coordinatorReducer: CombineReducers {
          TagRouteEffectsForCancellation(
            screenReducer: coordinatedScreensReducer,
            coordinatorId: cancellationId,
            routeAction: routeAction
          )
          coordinatorReducer
        },
        coordinatorId: cancellationId,
        routes: routes,
        getIdentifier: getIdentifier
      )
    } else {
      CombineReducers {
        coordinatorReducer
        coordinatedScreensReducer
      }
    }
  }
}

struct TagRouteEffectsForCancellation<ScreenReducer: ReducerProtocol, CoordinatorID: Hashable, RouteID: Hashable, RouteAction>: ReducerProtocol {
  typealias State = ScreenReducer.State
  typealias Action = ScreenReducer.Action

  let screenReducer: ScreenReducer
  let coordinatorId: CoordinatorID
  let routeAction: CasePath<Action, (RouteID, RouteAction)>

  func reduce(into state: inout State, action: Action) -> EffectTask<ScreenReducer.Action> {
    let effect = screenReducer.reduce(into: &state, action: action)

    if let (routeId, _) = routeAction.extract(from: action) {
      let identity = CancellationIdentity(coordinatorId: coordinatorId, routeId: routeId)
      return effect.cancellable(id: AnyHashable(identity))
    } else {
      return effect
    }
  }
}

struct CancelTaggedRouteEffectsOnDismiss<CoordinatorReducer: ReducerProtocol, CoordinatorID: Hashable, C: Collection, RouteID: Hashable>: ReducerProtocol {
  typealias State = CoordinatorReducer.State
  typealias Action = CoordinatorReducer.Action

  let coordinatorReducer: CoordinatorReducer
  let coordinatorId: CoordinatorID
  let routes: (State) -> C
  let getIdentifier: (C.Element, C.Index) -> RouteID

  func reduce(into state: inout State, action: Action) -> EffectTask<CoordinatorReducer.Action> {
    let preRoutes = routes(state)
    let effect = coordinatorReducer.reduce(into: &state, action: action)
    let postRoutes = routes(state)

    var effects: [EffectTask<Action>] = [effect]

    let preIds = zip(preRoutes, preRoutes.indices).map(getIdentifier)
    let postIds = zip(postRoutes, postRoutes.indices).map(getIdentifier)

    let dismissedIds = Set(preIds).subtracting(postIds)
    for dismissedId in dismissedIds {
      let identity = CancellationIdentity(coordinatorId: coordinatorId, routeId: dismissedId)
      effects.append(EffectTask<Action>.cancel(id: AnyHashable(identity)))
    }

    return EffectTask.merge(effects)
  }
}
