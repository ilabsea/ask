import React, { Component, PropTypes } from 'react'
import { connect } from 'react-redux'
import { withRouter } from 'react-router'
import * as projectActions from '../actions/projects'
import * as surveyActions from '../actions/surveys'
import * as questionnaireActions from '../actions/questionnaires'
import Title from '../components/Title'

class TitleContainer extends Component {
  // The title needs different entities to resolve
  // its view, depending on the current route.
  //
  // Those entities may or may not be available at the time of rendering,
  // since the user may be using a URL to access a part of the app
  // directly.
  //
  // So fetchEntities takes care of filling any gaps in the store
  // for the breadcrumb component to fully render.
  fetchEntities() {
    const { dispatch } = this.props
    const { projectId, surveyId, questionnaireId } = this.props.params

    if (questionnaireId) {
      dispatch(questionnaireActions.fetchQuestionnaireIfNeeded(projectId, questionnaireId))
    } else if (surveyId) {
      dispatch(surveyActions.fetchSurveyIfNeeded(projectId, surveyId))
    } else if (projectId) {
      dispatch(projectActions.fetchProjectIfNeeded(projectId))
    }
  }

  componentDidMount() {
    this.fetchEntities()
  }

  render() {
    const {
      params,
      project,
      survey,
      questionnaire,
      routes
    } = this.props

    return (
      <Title
        params={params}
        project={project}
        survey={survey}
        questionnaire={questionnaire}
        routes={routes} />
    )
  }
}

const findById = (id, col) => {
  if (col) {
    return col[id]
  } else {
    return undefined
  }
}

const mapStateToProps = (state, ownProps) => {
  return {
    params: ownProps.params,
    project: findById(ownProps.params.projectId, state.projects),
    survey: findById(ownProps.params.surveyId, state.surveys),
    questionnaire: findById(ownProps.params.questionnaireId, state.questionnaires),
    routes: ownProps.routes
  }
}

export default withRouter(connect(mapStateToProps)(TitleContainer))