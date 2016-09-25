import React, { Component, PropTypes } from 'react'
import { connect } from 'react-redux'
import { withRouter } from 'react-router'
import * as actions from '../actions/questionnaires'
import * as projectActions from '../actions/projects'
import { updateQuestionnaire } from '../api'
import QuestionnaireForm from '../components/QuestionnaireForm'

class QuestionnaireEdit extends Component {
  componentDidMount() {
    const { dispatch, projectId, questionnaireId } = this.props
    if (projectId && questionnaireId) {
      dispatch(actions.fetchQuestionnaire(projectId, questionnaireId))
      dispatch(projectActions.fetchProject(projectId))
    }
  }

  handleSubmit() {
    const { projectId, router, dispatch } = this.props
    return (questionnaire) => {
      updateQuestionnaire(projectId, questionnaire)
        .then(questionnaire => dispatch(actions.updateQuestionnaire(questionnaire)))
        .then(() => router.push(`/projects/${projectId}/questionnaires`))
    }
  }

  render(params) {
    const { children, questionnaire, project } = this.props
    return <QuestionnaireForm onSubmit={this.handleSubmit()} questionnaire={questionnaire} project={project} >{children}</QuestionnaireForm>
  }
}

const mapStateToProps = (state, ownProps) => ({
  projectId: ownProps.params.projectId,
  project: state.projects[ownProps.params.projectId] || {},
  questionnaireId: ownProps.params.questionnaireId,
  questionnaire: state.questionnaires[ownProps.params.questionnaireId]
})

export default withRouter(connect(mapStateToProps)(QuestionnaireEdit))