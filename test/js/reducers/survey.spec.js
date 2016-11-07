/* eslint-env mocha */
import expect from 'expect'
import assert from 'assert'
import { playActionsFromState } from '../spec_helper'
import reducer from '../../../web/static/js/reducers/survey'
import * as actions from '../../../web/static/js/actions/survey'
import * as questionnaireActions from '../../../web/static/js/actions/questionnaire'

describe('survey reducer', () => {
  const initialState = reducer(undefined, {})

  const playActions = playActionsFromState(initialState, reducer)

  it('has a sane initial state', () => {
    expect(initialState.fetching).toEqual(false)
    expect(initialState.filter).toEqual(null)
    expect(initialState.data).toEqual(null)
    expect(initialState.lastUpdatedAt).toEqual(null)
    expect(initialState.dirty).toEqual(false)
  })

  it('should fetch', () => {
    assert(!actions.shouldFetch({fetching: true, filter: {projectId: 1, id: 1}}, 1, 1))
    assert(actions.shouldFetch({fetching: true, filter: null}, 1, 1))
    assert(actions.shouldFetch({fetching: true, filter: {projectId: 1, id: 1}}, 2, 2))
    assert(actions.shouldFetch({fetching: false, filter: null}, 1, 1))
    assert(actions.shouldFetch({fetching: false, filter: {projectId: 1, id: 1}}, 1, 1))
  })

  it('fetches a survey', () => {
    const state = playActions([
      actions.fetch(1, 1)
    ])

    expect(state).toEqual({
      ...state,
      fetching: true,
      filter: {
        projectId: 1,
        id: 1
      },
      data: null
    })
  })

  it('receives a survey', () => {
    const state = playActions([
      actions.fetch(1, 1),
      actions.receive(survey)
    ])
    expect(state.fetching).toEqual(false)
    expect(state.data).toEqual(survey)
  })

  it('receiving a survey without an initial fetch should discard the survey', () => {
    const state = playActions([
      actions.receive(survey)
    ])
    expect(state.fetching).toEqual(false)
    expect(state.filter).toEqual(null)
    expect(state.data).toEqual(null)
  })

  it('clears data when fetching a different survey', () => {
    const state = playActions([
      actions.fetch(1, 1),
      actions.receive(survey),
      actions.fetch(2, 2)
    ])

    expect(state).toEqual({
      ...state,
      fetching: true,
      filter: {
        projectId: 2,
        id: 2
      },
      data: null
    })
  })

  it('keeps old data when fetching new data for the same filter', () => {
    const state = playActions([
      actions.fetch(1, 1),
      actions.receive(survey),
      actions.fetch(1, 1)
    ])

    expect(state).toEqual({
      ...state,
      fetching: true,
      data: survey
    })
  })

  it('ignores data received based on different filter', () => {
    const state = playActions([
      actions.fetch(2, 2),
      actions.receive(survey)
    ])

    expect(state).toEqual({
      ...state,
      filter: {projectId: 2, id: 2},
      fetching: true,
      data: null
    })
  })

  it('should be marked as dirty if something changed', () => {
    const state = playActions([
      actions.fetch(1, 1),
      actions.receive(survey),
      actions.toggleDay('wed')
    ])
    expect(state).toEqual({
      ...state,
      dirty: true
    })
  })

  it('shouldn\'t be marked as dirty if something changed in a different reducer', () => {
    const state = playActions([
      actions.fetch(1, 1),
      actions.receive(survey),
      questionnaireActions.changeName('foo')
    ])
    expect(state).toEqual({
      ...state,
      dirty: false
    })
  })

  it('should toggle a single day preserving the others', () => {
    const state = playActions([
      actions.fetch(1, 1),
      actions.receive(survey),
      actions.toggleDay('wed')
    ])
    expect(state.data.scheduleDayOfWeek)
    .toEqual({'sun': true, 'mon': true, 'tue': true, 'wed': false, 'thu': true, 'fri': true, 'sat': true})
  })
})

const survey = {
  'id': 1,
  'projectId': 1,
  'name': 'Foo',
  'cutoff': 123,
  'state': 'ready',
  'questionnaireId': 1,
  'scheduleDayOfWeek': {'sun': true, 'mon': true, 'tue': true, 'wed': true, 'thu': true, 'fri': true, 'sat': true},
  'scheduleStartTime': '02:00:00',
  'scheduleEndTime': '06:00:00',
  'channels': [1],
  'respondentsCount': 2
}
