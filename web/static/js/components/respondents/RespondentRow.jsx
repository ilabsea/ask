// @flow
import React, { Component } from 'react'
import dateformat from 'dateformat'
import languageNames from 'language-names'
import capitalize from 'lodash/capitalize'

type Props = {
  respondent: Respondent,
  responses: Response[],
  variantColumn: ?React$Element<*>
}

class RespondentRow extends Component {
  props: Props
  render() {
    const { respondent, responses, variantColumn } = this.props

    return (
      <tr key={respondent.id}>
        <td> {respondent.phoneNumber}</td>
        {responses.map((response) => {
          // For the 'language' variable we convert the code to the native name
          let value = response.value
          if (response.name == 'language') {
            value = languageNames[value] || value
          }

          return <td className='tdNowrap' key={parseInt(respondent.id) + response.name}>{value}</td>
        })}
        {variantColumn}
        <td>
          {capitalize(respondent.disposition)}
        </td>
        <td>
          {respondent.date ? dateformat(new Date(respondent.date), 'mmm d, yyyy HH:MM') : '-'}
        </td>
      </tr>
    )
  }
}

export default RespondentRow
