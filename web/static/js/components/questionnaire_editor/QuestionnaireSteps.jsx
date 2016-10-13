import React, { PropTypes } from 'react'
import Card from '../Card'
import QuestionnaireClosedStep from './QuestionnaireClosedStep'
import StepEditor from './StepEditor'

const StepsList = ({steps}) => {
  if (steps.length !== 0) {
    return (
      <Card>
        <ul className='collection'>
          { steps.map((step) => (
            <QuestionnaireClosedStep step={step} key={step.id} />
          ))}
        </ul>
      </Card>
    )
  } else {
    return null
  }
}

const QuestionnaireSteps = ({ steps }) => {
  if (steps) {
    if (!steps.current) {
      // All collapsed
      return <StepsList steps={steps.ids.map((id) => steps.items[id])} />
    } else {
      const itemIndex = steps.ids.findIndex(stepId => stepId === steps.current.id)

      // Only one expanded
      const stepsBefore = steps.ids.slice(0, itemIndex).map((id) => steps.items[id])
      const currentStep = steps.items[steps.current.id]
      const stepsAfter = steps.ids.slice(itemIndex + 1).map((id) => steps.items[id])

      return (
        <div className='row'>
          <div className='col s12'>
            <StepsList steps={stepsBefore} />
            <StepEditor step={currentStep} />
            <StepsList steps={stepsAfter} />
          </div>
        </div>
      )
    }
  } else {
    return (
      <div>
        Sorry! There are no steps here and there's no way to create them yet. It's a bit embarrasing, but the Ask team is working really hard on that feature. In the meantime, if you save this questionnaire we'll create two steps for you to play around.
      </div>
    )
  }
}

QuestionnaireSteps.propTypes = {
  steps: PropTypes.object
}

StepsList.propTypes = {
  steps: PropTypes.object
}

export default QuestionnaireSteps
