import React, { Component } from 'react'
import merge from 'lodash/merge'
import { withRouter } from 'react-router'
import { connect } from 'react-redux'
import { updateSurvey } from '../api'
import * as actions from '../actions/surveys'

class SurveyWizardCutoffStep extends Component {
  handleSubmit(survey) {
    const { dispatch } = this.props
    updateSurvey(survey.projectId, survey)
      .then(updatedSurvey => dispatch(actions.setSurvey(updatedSurvey)))
      .catch((e) => dispatch(actions.receiveSurveysError(e)))
  }

  render() {
    let resultsInput
    const { survey } = this.props
    if (!survey) {
      return <div>Loading...</div>
    }
    return (
      <div className="col s12 m7 offset-m1">
        <div className="row">
          <div className="col s12">
            <h4>Configure cutoff rules</h4>
            <p className="flow-text">
              Cutoff rules define when the survey will stop. You can use one or more of these options. If you don't select any, the survey will be sent to all respondents.
            </p>
          </div>
        </div>
        <div className="row">
          <div className=" input-field col s12">
            <input id='completed-results' type="text" defaultValue={survey.cutoff} ref={ node => { resultsInput = node } }/>
            <label className="active" htmlFor='completed-results'>Completed results</label>
          </div>
        </div>
        <div className="row">
          <div className="col s12">
            <button type="button" className="btn waves-effect waves-light" onClick={() =>
              this.handleSubmit(merge({}, survey, { cutoff: resultsInput.value }))
            }>
              Submit
            </button>
          </div>
        </div>
      </div>
    )
  }
}

const mapStateToProps = (state, ownProps) => ({
  projectId: ownProps.params.projectId,
  survey: state.surveys[ownProps.params.surveyId]
})

export default withRouter(connect(mapStateToProps)(SurveyWizardCutoffStep));
