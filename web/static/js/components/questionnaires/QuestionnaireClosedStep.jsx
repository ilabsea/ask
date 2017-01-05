// @flow
import React, { Component } from 'react'
import classNames from 'classnames'
import { UntitledIfEmpty, Card } from '../ui'
import DraggableStep from './DraggableStep'
import { connect } from 'react-redux'
import { hasErrors } from '../../questionnaireErrors'

type Props = {
  step: Step,
  onClick: Function,
  hasErrors: boolean
};

class QuestionnaireClosedStep extends Component {
  props: Props

  render() {
    const { step, onClick, hasErrors } = this.props

    const stepIconClass = classNames({
      'material-icons left': true,
      'sharp': step.type === 'numeric',
      'text-error': hasErrors
    })

    const stepIconFont = (() => {
      if (step.type === 'multiple-choice') {
        return 'list'
      } else if (step.type === 'numeric') {
        return 'dialpad'
      } else {
        return 'language'
      }
    })()

    return (
      <DraggableStep step={step}>
        <Card>
          <div className='card-content closed-step'>
            <div>
              <a href='#!' className='truncate' onClick={event => {
                event.preventDefault()
                onClick(step.id)
              }}>
                <i className={stepIconClass}>{stepIconFont}</i>
                <UntitledIfEmpty className={classNames({'text-error': hasErrors})} text={step.title} entityName='question' />
                <i className={classNames({'material-icons right grey-text': true, 'text-error': hasErrors})}>expand_more</i>
              </a>
            </div>
          </div>
        </Card>
      </DraggableStep>
    )
  }
}

const mapStateToProps = (state, ownProps) => ({
  hasErrors: hasErrors(state.questionnaire, ownProps.step)
})

export default connect(mapStateToProps)(QuestionnaireClosedStep)
