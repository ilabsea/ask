import React, { Component, PropTypes } from 'react'
import { bindActionCreators } from 'redux'
import { connect } from 'react-redux'
import { CardTable, AddButton, ConfirmationModal } from '../ui'
import * as actions from '../../actions/collaborators'

class CollaboratorIndex extends Component {
  componentDidMount() {
    const { projectId } = this.props
    if (projectId) {
      this.props.actions.fetchCollaborators(projectId)
    }
  }

  inviteCollaborator() {
    $('#addCollaborator').modal('open')
  }

  render() {
    const { collaborators } = this.props
    if (!collaborators) {
      return <div>Loading...</div>
    }
    const title = `${collaborators.length} ${(collaborators.length == 1) ? ' collaborator' : ' collaborators'}`

    return (
      <div>
        <AddButton text='Invite collaborator' onClick={() => this.inviteCollaborator()} />
        <ConfirmationModal modalId='addCollaborator' modalText='Add Collaborator' header='Invite collaborators' confirmationText='accept' onConfirm={(event) => event.preventDefault()} style={{maxWidth: '600px'}} />
        <div>
          <CardTable title={title}>
            <thead>
              <tr>
                <th>Email</th>
                <th>Role</th>
              </tr>
            </thead>
            <tbody>
              { collaborators.map(c => {
                return (
                  <tr key={c.email}>
                    <td> {c.email} </td>
                    <td> {c.role} </td>
                  </tr>
                )
              })}
            </tbody>
          </CardTable>
        </div>
      </div>
    )
  }
}

CollaboratorIndex.propTypes = {
  projectId: PropTypes.string.isRequired,
  collaborators: PropTypes.array,
  actions: PropTypes.object.isRequired
}

const mapDispatchToProps = (dispatch) => ({
  actions: bindActionCreators(actions, dispatch)
})

const mapStateToProps = (state, ownProps) => ({
  projectId: ownProps.params.projectId,
  collaborators: state.collaborators.items
})

export default connect(mapStateToProps, mapDispatchToProps)(CollaboratorIndex)
